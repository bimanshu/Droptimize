// libvpx for Swift. Swift can't call C variadic functions or function-like macros, which is how
// libvpx starts an encoder and sets its options, so these small wrappers do it from C.
#include "../Vendor/libvpx/include/vpx/vpx_encoder.h"
#include "../Vendor/libvpx/include/vpx/vp8cx.h"

static inline vpx_codec_err_t droptimize_vpx_vp9_init(vpx_codec_ctx_t *ctx, const vpx_codec_enc_cfg_t *cfg) {
    return vpx_codec_enc_init(ctx, vpx_codec_vp9_cx(), cfg, 0);
}

// Every control Droptimize sets takes an int or unsigned int, which pass the same way.
static inline vpx_codec_err_t droptimize_vpx_control(vpx_codec_ctx_t *ctx, int id, int value) {
    return vpx_codec_control_(ctx, id, value);
}
