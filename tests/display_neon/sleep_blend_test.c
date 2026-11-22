/*
 * Bit-exactness test for gralloc_v1/epdc_pixel_ops.h (DISPLAY_COPY_NEON_PLAN §2, §4).
 * Built for ARMv7+NEON and run under qemu-arm by run_tests.sh; also builds on
 * the host, where only the scalar path exists.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "epdc_pixel_ops.h"

static uint32_t rng_state = 0x12345678u;
static uint32_t rnd(void)
{
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 17;
    rng_state ^= rng_state << 5;
    return rng_state;
}

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { if (failures++ < 20) { \
    printf("FAIL %s:%d ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } } while (0)

static void test_div255_identity(void)
{
    for (uint32_t x = 0; x <= 255u * 255u; ++x) {
        const uint32_t t = x + 127;
        CHECK(((t + 1 + (t >> 8)) >> 8) == t / 255, "div255 x=%u", x);
    }
}

/* Every (alpha, source channel, destination channel) triple, all channels. */
static void test_blend_exhaustive_channels(void)
{
    enum { N = 64 * 8 };
    uint8_t src[N * 4];
    uint16_t base[N], out_ref[N], out_neon[N];
    for (int a = 0; a < 256; ++a) {
        for (int s0 = 0; s0 < 256; s0 += 8) {
            int n = 0;
            for (int s = s0; s < s0 + 8; ++s) {
                for (int d = 0; d < 64; ++d, ++n) {
                    src[n * 4 + 0] = (uint8_t)a;
                    src[n * 4 + 1] = (uint8_t)s;
                    src[n * 4 + 2] = (uint8_t)(255 - s);
                    src[n * 4 + 3] = (uint8_t)(s ^ 0x5a);
                    base[n] = (uint16_t)(((d & 31) << 11) | (d << 5) | (31 - (d & 31)));
                }
            }
            const int t_ref = e70q10_sleep_blend_row_scalar(src, base, out_ref, N);
            const int t_neon = e70q10_sleep_blend_row(src, base, out_neon, N, 1);
            CHECK(t_ref == t_neon, "transparent flag a=%d", a);
            for (int i = 0; i < N; ++i) {
                CHECK(out_ref[i] == out_neon[i], "a=%d i=%d src=%02x%02x%02x%02x base=%04x ref=%04x neon=%04x",
                        a, i, src[i * 4], src[i * 4 + 1], src[i * 4 + 2], src[i * 4 + 3],
                        base[i], out_ref[i], out_neon[i]);
                /* Scalar row must equal the original per-pixel framebuffer.cpp code. */
                const uint16_t expect = src[i * 4] == 0 ? base[i] :
                        e70q10_blend_straight_argb_over_rgb565(src + i * 4, base[i]);
                CHECK(out_ref[i] == expect, "scalar row mismatch i=%d", i);
            }
        }
    }
}

/* Random rows: every length 0..80, odd source offsets, aliasing out == base. */
static void test_blend_random_rows(void)
{
    uint8_t src_buf[100 * 4 + 4];
    uint16_t base[101], alias[101], out_ref[101], out_neon[101];
    for (int iter = 0; iter < 20000; ++iter) {
        const int len = iter % 81;
        const int src_off = (iter / 81) & 3;
        const int dst_off = (iter / 324) & 1;
        uint8_t* src = src_buf + src_off;
        for (int i = 0; i < len; ++i) {
            const uint32_t r = rnd();
            const int mode = (r >> 24) & 3;
            src[i * 4] = mode == 0 ? 0 : mode == 1 ? 255 : (uint8_t)r;
            src[i * 4 + 1] = (uint8_t)(r >> 8);
            src[i * 4 + 2] = (uint8_t)(r >> 16);
            src[i * 4 + 3] = (uint8_t)rnd();
            base[dst_off + i] = (uint16_t)rnd();
        }
        memcpy(alias, base, sizeof(base));
        const int t_ref = e70q10_sleep_blend_row_scalar(src, base + dst_off, out_ref, len);
        const int t_neon = e70q10_sleep_blend_row(src, base + dst_off, out_neon + dst_off, len, 1);
        const int t_alias = e70q10_sleep_blend_row(src, alias + dst_off, alias + dst_off, len, 1);
        CHECK(t_ref == t_neon && t_ref == t_alias, "flag iter=%d", iter);
        for (int i = 0; i < len; ++i) {
            CHECK(out_ref[i] == out_neon[dst_off + i], "row iter=%d i=%d", iter, i);
            CHECK(out_ref[i] == alias[dst_off + i], "alias iter=%d i=%d", iter, i);
        }
    }
}

static void test_rows_differ(void)
{
    uint8_t a[400], b[400];
    for (int len = 0; len <= 300; ++len) {
        for (int off = 0; off < 3; ++off) {
            for (int i = 0; i < len; ++i)
                a[off + i] = b[off + i] = (uint8_t)rnd();
            CHECK(!e70q10_rows_differ(a + off, b + off, (size_t)len), "equal len=%d", len);
            for (int pos = 0; pos < len; ++pos) {
                b[off + pos] ^= (uint8_t)(1u << (pos & 7));
                CHECK(e70q10_rows_differ(a + off, b + off, (size_t)len), "diff len=%d pos=%d", len, pos);
                b[off + pos] = a[off + pos];
            }
        }
    }
}

int main(void)
{
    printf("epdc_pixel_ops NEON=%d\n", E70Q10_EPDC_HAVE_NEON);
    test_div255_identity();
    test_blend_exhaustive_channels();
    test_blend_random_rows();
    test_rows_differ();
    printf("%s (%d failures)\n", failures ? "FAILED" : "PASSED", failures);
    return failures ? 1 : 0;
}
