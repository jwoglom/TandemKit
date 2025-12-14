#include "MbedTLSShim.h"
#include <stdlib.h>
#include <string.h>

// Best-effort zeroization that should not be optimized away.
static void mbedtls_shim_zeroize(void *ptr, size_t len) {
    if (ptr == NULL || len == 0) {
        return;
    }
    volatile unsigned char *p = (volatile unsigned char *)ptr;
    while (len--) {
        *p++ = 0;
    }
}

static void mbedtls_shim_secure_free(void *ptr, size_t len) {
    if (ptr == NULL) {
        return;
    }
    mbedtls_shim_zeroize(ptr, len);
    free(ptr);
}

static int mbedtls_shim_random(void *p_rng, unsigned char *output, size_t length) {
    if (p_rng == NULL || output == NULL) {
        return -1;
    }

    mbedtls_shim_jpake_client *client = (mbedtls_shim_jpake_client *)p_rng;
    if (client->rng != NULL) {
        return client->rng(client->rng_context, output, length);
    }

    return mbedtls_ctr_drbg_random(&client->drbg, output, length);
}

static int mbedtls_shim_seed_rng(mbedtls_shim_jpake_client *client) {
    mbedtls_entropy_init(&client->entropy);
    mbedtls_ctr_drbg_init(&client->drbg);

    const char *pers = "tandemkit-jpake";
    return mbedtls_ctr_drbg_seed(&client->drbg, mbedtls_entropy_func, &client->entropy, (const unsigned char *)pers, strlen(pers));
}

static int mbedtls_shim_setup_client(mbedtls_shim_jpake_client *client, const uint8_t *password, size_t password_len) {
    client->is_ready = 0;
    client->rng = NULL;
    client->rng_context = NULL;
    mbedtls_ecjpake_init(&client->ctx);
    int ret = mbedtls_shim_seed_rng(client);
    if (ret != 0) {
        // Avoid leaking partially-initialized state when Swift init throws.
        mbedtls_shim_jpake_free(client);
        return ret;
    }

    ret = mbedtls_ecjpake_setup(&client->ctx, MBEDTLS_MD_SHA256, MBEDTLS_ECP_DP_SECP256R1, MBEDTLS_ECJPAKE_CLIENT, password, password_len, mbedtls_shim_random, client);
    if (ret != 0) {
        // Avoid leaking partially-initialized state when Swift init throws.
        mbedtls_shim_jpake_free(client);
        return ret;
    }

    client->is_ready = 1;
    return 0;
}

int mbedtls_shim_jpake_init(mbedtls_shim_jpake_client *client, const uint8_t *password, size_t password_len) {
    if (client == NULL || password == NULL || password_len == 0) {
        return -1;
    }
    client->is_ready = 0;
    return mbedtls_shim_setup_client(client, password, password_len);
}

static int mbedtls_shim_write_with_grow(
    int (*writer)(mbedtls_ecjpake_context *, unsigned char *, size_t, size_t *, int (*)(void *, unsigned char *, size_t), void *),
    mbedtls_shim_jpake_client *client,
    mbedtls_shim_buffer *buffer,
    size_t initial_capacity,
    size_t max_capacity
) {
    if (client == NULL || buffer == NULL || client->is_ready == 0) {
        return -1;
    }

    buffer->bytes = NULL;
    buffer->length = 0;

    if (initial_capacity == 0) {
        initial_capacity = 1;
    }

    size_t capacity = initial_capacity;
    while (capacity <= max_capacity) {
        uint8_t *bytes = (uint8_t *)malloc(capacity);
        if (bytes == NULL) {
            return -1;
        }

        size_t out_len = 0;
        int ret = writer(&client->ctx, bytes, capacity, &out_len, mbedtls_ctr_drbg_random, &client->drbg);
        if (ret == 0) {
            // Zero any unused tail so freeing/shrinking can't leak previous heap contents.
            if (out_len < capacity) {
                mbedtls_shim_zeroize(bytes + out_len, capacity - out_len);
            }

            // Prefer returning an exactly-sized allocation so buffer_free can wipe all bytes.
            if (out_len > 0 && out_len < capacity) {
                uint8_t *shrunk = (uint8_t *)realloc(bytes, out_len);
                if (shrunk != NULL) {
                    bytes = shrunk;
                }
            }

            buffer->bytes = bytes;
            buffer->length = out_len;
            return 0;
        }

        if (ret == MBEDTLS_ERR_ECP_BUFFER_TOO_SMALL) {
            mbedtls_shim_secure_free(bytes, capacity);

            // Some Mbed TLS builds populate out_len with the required size.
            size_t next = (out_len > capacity) ? out_len : (capacity * 2);
            if (next <= capacity) {
                next = capacity + 1;
            }
            capacity = next;
            continue;
        }

        mbedtls_shim_secure_free(bytes, capacity);
        return ret;
    }

    return MBEDTLS_ERR_ECP_BUFFER_TOO_SMALL;
}

static int mbedtls_shim_write_round(int (*writer)(mbedtls_ecjpake_context *, unsigned char *, size_t, size_t *, int (*)(void *, unsigned char *, size_t), void *), mbedtls_shim_jpake_client *client, mbedtls_shim_buffer *buffer) {
    // Don't rely on NULL/0 "query" calls; some Mbed TLS builds reject that usage.
    return mbedtls_shim_write_with_grow(writer, client, buffer, 512, 16384);
}

int mbedtls_shim_jpake_round1(mbedtls_shim_jpake_client *client, mbedtls_shim_buffer *buffer) {
    return mbedtls_shim_write_round(mbedtls_ecjpake_write_round_one, client, buffer);
}

int mbedtls_shim_jpake_read_round1(mbedtls_shim_jpake_client *client, const uint8_t *bytes, size_t length) {
    if (client == NULL || bytes == NULL || length == 0 || client->is_ready == 0) {
        return -1;
    }
    return mbedtls_ecjpake_read_round_one(&client->ctx, bytes, length);
}

int mbedtls_shim_jpake_round2(mbedtls_shim_jpake_client *client, mbedtls_shim_buffer *buffer) {
    return mbedtls_shim_write_round(mbedtls_ecjpake_write_round_two, client, buffer);
}

int mbedtls_shim_jpake_read_round2(mbedtls_shim_jpake_client *client, const uint8_t *bytes, size_t length) {
    if (client == NULL || bytes == NULL || length == 0 || client->is_ready == 0) {
        return -1;
    }
    return mbedtls_ecjpake_read_round_two(&client->ctx, bytes, length);
}

int mbedtls_shim_jpake_derive(mbedtls_shim_jpake_client *client, mbedtls_shim_buffer *buffer) {
    // Don't rely on NULL/0 "query" calls; some Mbed TLS builds reject that usage.
    return mbedtls_shim_write_with_grow(mbedtls_ecjpake_derive_secret, client, buffer, 64, 4096);
}

void mbedtls_shim_jpake_set_rng(mbedtls_shim_jpake_client *client, mbedtls_shim_rng_callback rng, void *context) {
    if (client == NULL) {
        return;
    }

    client->rng = rng;
    client->rng_context = context;
}

void mbedtls_shim_buffer_free(mbedtls_shim_buffer *buffer) {
    if (buffer == NULL || buffer->bytes == NULL) {
        return;
    }
    // Secrets (e.g., derived session keys) must be wiped before freeing.
    mbedtls_shim_secure_free(buffer->bytes, buffer->length);
    buffer->bytes = NULL;
    buffer->length = 0;
}

void mbedtls_shim_jpake_free(mbedtls_shim_jpake_client *client) {
    if (client == NULL) {
        return;
    }
    mbedtls_ecjpake_free(&client->ctx);
    mbedtls_ctr_drbg_free(&client->drbg);
    mbedtls_entropy_free(&client->entropy);
    client->rng = NULL;
    client->rng_context = NULL;
    client->is_ready = 0;
}
