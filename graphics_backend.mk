# Select the graphics bring-up path without maintaining separate products.
# AGL is the safe default for the GPU-less i.MX6SoloLite target.
E70Q10_GRAPHICS_BACKEND ?= agl

ifeq ($(filter $(E70Q10_GRAPHICS_BACKEND),agl mesa),)
$(error Unsupported E70Q10_GRAPHICS_BACKEND="$(E70Q10_GRAPHICS_BACKEND)"; use agl or mesa)
endif
