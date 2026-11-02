#pragma once
/* Pure-C bounds-checked AppleDouble reader. No platform dependencies. */
#include <stdint.h>
#include <stddef.h>
typedef struct { uint32_t finderOffset, finderLength, resourceOffset, resourceLength; uint16_t count; int valid; } ADParts;
ADParts ad_parts(const unsigned char *p, size_t n);
int ad_all_zero(const unsigned char *p, size_t n);
int ad_path_contains(const char *root, const char *child);
