#ifndef TANDEMKIT_MBEDTLS_SHIM_H
#define TANDEMKIT_MBEDTLS_SHIM_H

#include <stddef.h>
#include <stdint.h>
#include "MbedTLS.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t *bytes;
    size_t length;
} mbedtls_shim_buffer;

typedef struct {
    mbedtls_ecjpake_context ctx;
    mbedtls_ctr_drbg_context drbg;
    mbedtls_entropy_context entropy;
    int (*rng)(void *context, unsigned char *output, size_t length);
    void *rng_context;
    int is_ready;
} mbedtls_shim_jpake_client;

typedef int (*mbedtls_shim_rng_callback)(void *context, unsigned char *output, size_t length);

int mbedtls_shim_jpake_init(mbedtls_shim_jpake_client *client, const uint8_t *password, size_t password_len);
int mbedtls_shim_jpake_round1(mbedtls_shim_jpake_client *client, mbedtls_shim_buffer *buffer);
int mbedtls_shim_jpake_read_round1(mbedtls_shim_jpake_client *client, const uint8_t *bytes, size_t length);
int mbedtls_shim_jpake_round2(mbedtls_shim_jpake_client *client, mbedtls_shim_buffer *buffer);
int mbedtls_shim_jpake_read_round2(mbedtls_shim_jpake_client *client, const uint8_t *bytes, size_t length);
int mbedtls_shim_jpake_derive(mbedtls_shim_jpake_client *client, mbedtls_shim_buffer *buffer);
void mbedtls_shim_jpake_set_rng(mbedtls_shim_jpake_client *client, mbedtls_shim_rng_callback rng, void *context);
void mbedtls_shim_buffer_free(mbedtls_shim_buffer *buffer);
void mbedtls_shim_jpake_free(mbedtls_shim_jpake_client *client);

#ifdef __cplusplus
}
#endif

#endif // TANDEMKIT_MBEDTLS_SHIM_H
