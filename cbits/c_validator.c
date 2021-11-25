#include <stddef.h>

int z_validate_utf8_avx2(const char *data, size_t len);

#include "../faster-utf8-validator/z_validate.c"

int _hs_text_is_valid_utf8(uint8_t *buf, size_t len) {
    return z_validate_utf8_avx2(buf, len);
}
