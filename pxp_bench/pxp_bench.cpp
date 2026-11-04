extern "C" {
#include <pxp_lib.h>
}

#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

namespace {

constexpr unsigned kSourceWidth = 1404;
constexpr unsigned kSourceHeight = 1872;
constexpr unsigned kOutputWidth = 1872;
constexpr unsigned kOutputHeight = 1404;
constexpr unsigned kOutputStride = 1888;
constexpr int kRuns = 5;

uint64_t nowNs() {
    timespec ts{};
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return static_cast<uint64_t>(ts.tv_sec) * 1000000000ULL + ts.tv_nsec;
}

uint32_t pxpXrgb(unsigned red, unsigned green, unsigned blue) {
    // PXP XRGB32 consumes a little-endian 0x00RRGGBB word.
    return (red << 16) | (green << 8) | blue;
}

void fillPattern(uint32_t* pixels) {
    for (unsigned y = 0; y < kSourceHeight; ++y) {
        for (unsigned x = 0; x < kSourceWidth; ++x) {
            uint32_t color;
            if (y < kSourceHeight / 2)
                color = x < kSourceWidth / 2
                        ? pxpXrgb(255, 0, 0)       // source top-left
                        : pxpXrgb(0, 255, 0);      // source top-right
            else
                color = x < kSourceWidth / 2
                        ? pxpXrgb(0, 0, 255)       // source bottom-left
                        : pxpXrgb(255, 255, 255);  // source bottom-right
            pixels[y * kSourceWidth + x] = color;
        }
    }
}

uint16_t sample(const uint16_t* output, unsigned x, unsigned y) {
    return output[y * kOutputStride + x];
}

void releaseMemory(pxp_mem_desc* memory) {
    if (memory->phys_addr != 0)
        pxp_put_mem(memory);
    memset(memory, 0, sizeof(*memory));
}

}  // namespace

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);

    if (pxp_init() != 0) {
        printf("FAIL pxp_init errno=%d\n", errno);
        return 1;
    }

    pxp_chan_handle_t channel{};
    pxp_mem_desc input{};
    pxp_mem_desc output{};
    pxp_config_data config{};
    uint64_t total = 0;
    uint64_t minimum = UINT64_MAX;
    uint64_t maximum = 0;
    uint64_t fillStart = 0;
    uint64_t fillElapsed = 0;
    int status = 1;

    if (pxp_request_channel(&channel) != 0) {
        printf("FAIL request_channel errno=%d\n", errno);
        goto done;
    }

    input.size = kSourceWidth * kSourceHeight * sizeof(uint32_t);
    input.mtype = MEMORY_TYPE_WC;
    output.size = kOutputStride * kOutputHeight * sizeof(uint16_t);
    output.mtype = MEMORY_TYPE_UNCACHED;
    if (pxp_get_mem(&input) != 0 || pxp_get_mem(&output) != 0) {
        printf("FAIL allocate input_size=%u input_handle=%u input_phys=%08lx "
               "input_virt=%08x output_size=%u output_handle=%u "
               "output_phys=%08lx output_virt=%08x errno=%d\n",
               input.size, input.handle,
               static_cast<unsigned long>(input.phys_addr), input.virt_uaddr,
               output.size, output.handle,
               static_cast<unsigned long>(output.phys_addr), output.virt_uaddr,
               errno);
        goto release_channel;
    }

    fillStart = nowNs();
    fillPattern(reinterpret_cast<uint32_t*>(
            static_cast<uintptr_t>(input.virt_uaddr)));
    fillElapsed = nowNs() - fillStart;
    memset(reinterpret_cast<void*>(static_cast<uintptr_t>(output.virt_uaddr)),
           0, output.size);

    config.s0_param.paddr = input.phys_addr;
    config.s0_param.width = kSourceWidth;
    config.s0_param.height = kSourceHeight;
    config.s0_param.stride = kSourceWidth;
    config.s0_param.pixel_fmt = PXP_PIX_FMT_XRGB32;
    config.s0_param.color_key = static_cast<unsigned>(-1);
    config.proc_data.srect.left = 0;
    config.proc_data.srect.top = 0;
    config.proc_data.srect.width = kSourceWidth;
    config.proc_data.srect.height = kSourceHeight;

    config.out_param.paddr = output.phys_addr;
    config.out_param.width = kOutputWidth;
    config.out_param.height = kOutputHeight;
    config.out_param.stride = kOutputStride;
    config.out_param.pixel_fmt = PXP_PIX_FMT_RGB565;
    config.proc_data.drect.left = 0;
    config.proc_data.drect.top = 0;
    config.proc_data.drect.width = kOutputWidth;
    config.proc_data.drect.height = kOutputHeight;
    config.proc_data.rotate = 270;

    for (int run = 0; run < kRuns; ++run) {
        const uint64_t start = nowNs();
        if (pxp_config_channel(&channel, &config) != 0 ||
            pxp_start_channel(&channel) != 0 ||
            pxp_wait_for_completion(&channel, 10) != 0) {
            printf("FAIL run=%d errno=%d\n", run, errno);
            goto release_memory;
        }
        const uint64_t elapsed = nowNs() - start;
        total += elapsed;
        if (elapsed < minimum) minimum = elapsed;
        if (elapsed > maximum) maximum = elapsed;
    }

    {
        const uint16_t* pixels = reinterpret_cast<const uint16_t*>(
                static_cast<uintptr_t>(output.virt_uaddr));
        printf("PASS pxp rotate=270 src=%ux%u dst=%ux%u stride=%u "
               "runs=%d min_ms=%.3f avg_ms=%.3f max_ms=%.3f "
               "staging_fill_ms=%.3f\n",
               kSourceWidth, kSourceHeight, kOutputWidth, kOutputHeight,
               kOutputStride, kRuns, minimum / 1000000.0,
               total / static_cast<double>(kRuns) / 1000000.0,
               maximum / 1000000.0, fillElapsed / 1000000.0);
        uint16_t* copied = static_cast<uint16_t*>(malloc(output.size));
        if (copied != nullptr) {
            uint64_t copyTotal = 0;
            for (int run = 0; run < kRuns; ++run) {
                const uint64_t copyStart = nowNs();
                memcpy(copied, pixels, output.size);
                copyTotal += nowNs() - copyStart;
            }
            printf("uncached_copy bytes=%u avg_ms=%.3f\n",
                   output.size,
                   copyTotal / static_cast<double>(kRuns) / 1000000.0);
            free(copied);
        }
        printf("corners TL=%04x TR=%04x BL=%04x BR=%04x "
               "expected270 TL=07e0 TR=ffff BL=f800 BR=001f\n",
               sample(pixels, 0, 0),
               sample(pixels, kOutputWidth - 1, 0),
               sample(pixels, 0, kOutputHeight - 1),
               sample(pixels, kOutputWidth - 1, kOutputHeight - 1));
        unsigned minX = kOutputWidth;
        unsigned minY = kOutputHeight;
        unsigned maxX = 0;
        unsigned maxY = 0;
        for (unsigned y = 0; y < kOutputHeight; ++y) {
            for (unsigned x = 0; x < kOutputWidth; ++x) {
                if (sample(pixels, x, y) != 0) {
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
            }
        }
        printf("nonzero_bounds x=%u..%u y=%u..%u center=%04x\n",
               minX, maxX, minY, maxY,
               sample(pixels, kOutputWidth / 2, kOutputHeight / 2));
    }
    status = 0;

release_memory:
    releaseMemory(&output);
    releaseMemory(&input);
release_channel:
    pxp_release_channel(&channel);
done:
    pxp_uninit();
    return status;
}
