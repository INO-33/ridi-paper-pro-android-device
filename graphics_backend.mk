# Stock 4.4.2 uses PixelFlinger/GLES1 to render an RGB565 framebuffer target
# directly into the EPDC's page-flippable 1888-pixel-stride buffers. Keep that
# known-good display path as the default until Android 8 reaches the same
# target-to-fb_post boundary. Mesa remains an explicit GLES2 compatibility
# experiment; it must not silently become SurfaceFlinger's primary compositor.
E70Q10_GRAPHICS_BACKEND ?= agl

ifeq ($(filter $(E70Q10_GRAPHICS_BACKEND),agl mesa),)
$(error Unsupported E70Q10_GRAPHICS_BACKEND="$(E70Q10_GRAPHICS_BACKEND)"; use agl or mesa)
endif
