#include "MbedTLSShim.h"
#include <stdlib.h>
#include <string.h>

static int mbedtls_shim_seed_rng(mbedtls_shim_jpake_client *client) {
    mbedtls_entropy_init(&client->entropy);
    mbedtls_ctr_drbg_init(&client->drbg);

    const char *pers = "tandemkit-jpake";
    return mbedtls_ctr_drbg_seed(&client->drbg, mbedtls_entropy_func, &client->entropy, (const unsigned char *)pers, strlen(pers));
}

static int mbedtls_shim_setup_client(mbedtls_shim_jpake_client *client, const uint8_t *password, size_t password_len) {
    mbedtls_ecjpake_init(&client->ctx);
    int ret = mbedtls_shim_seed_rng(client);
    if (ret != 0) {
        return ret;
    }

    ret = mbedtls_ecjpake_setup(&client->ctx, MBEDTLS_MD_SHA256, MBEDTLS_ECP_DP_SECP256R1, MBEDTLS_ECJPAKE_CLIENT, password, password_len, mbedtls_ctr_drbg_random, &client->drbg);
    if (ret == 0) {
        client->is_ready = 1;
    }
    return ret;
}

int mbedtls_shim_jpake_init(mbedtls_shim_jpake_client *client, const uint8_t *password, size_t password_len) {
    if (client == NULL || password == NULL || password_len == 0) {
        return -1;
    }
    client->is_ready = 0;
    return mbedtls_shim_setup_client(client, password, password_len);
}

static int mbedtls_shim_write_round(int (*writer)(mbedtls_ecjpake_context *, unsigned char *, size_t, size_t *, int (*)(void *, unsigned char *, size_t), void *), mbedtls_shim_jpake_client *client, mbedtls_shim_buffer *buffer) {
    if (client == NULL || buffer == NULL || client->is_ready == 0) {
        return -1;
    }

    size_t required = 0;
    int ret = writer(&client->ctx, NULL, 0, &required, mbedtls_ctr_drbg_random, &client->drbg);
    if (ret != MBEDTLS_ERR_ECP_BUFFER_TOO_SMALL && ret != 0) {
        return ret;
    }

    if (required == 0) {
        required = 512;
    }

    uint8_t *bytes = (uint8_t *)malloc(required);
    if (bytes == NULL) {
        return -1;
    }

    ret = writer(&client->ctx, bytes, required, &required, mbedtls_ctr_drbg_random, &client->drbg);
    if (ret != 0) {
        free(bytes);
        return ret;
    }

    buffer->bytes = bytes;
    buffer->length = required;
    return 0;
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
    if (client == NULL || buffer == NULL || client->is_ready == 0) {
        return -1;
    }

    size_t required = 0;
    int ret = mbedtls_ecjpake_derive_secret(&client->ctx, NULL, 0, &required, mbedtls_ctr_drbg_random, &client->drbg);
    if (ret != MBEDTLS_ERR_ECP_BUFFER_TOO_SMALL && ret != 0) {
        return ret;
    }

    if (required == 0) {
        required = 64;
    }

    uint8_t *bytes = (uint8_t *)malloc(required);
    if (bytes == NULL) {
        return -1;
    }

    ret = mbedtls_ecjpake_derive_secret(&client->ctx, bytes, required, &required, mbedtls_ctr_drbg_random, &client->drbg);
    if (ret != 0) {
        free(bytes);
        return ret;
    }

    buffer->bytes = bytes;
    buffer->length = required;
    return 0;
}

void mbedtls_shim_buffer_free(mbedtls_shim_buffer *buffer) {
    if (buffer == NULL || buffer->bytes == NULL) {
        return;
    }
    free(buffer->bytes);
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
    client->is_ready = 0;
}
