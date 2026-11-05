// libaom's AV1 encoder for Swift. Swift can't call C variadic functions or function-like macros,
// which is how libaom starts an encoder and sets its options, so these small wrappers do it from C.
#include "../Vendor/libavif/include/aom/aom_encoder.h"
#include "../Vendor/libavif/include/aom/aomcx.h"

static inline aom_codec_err_t droptimize_aom_av1_init(aom_codec_ctx_t *ctx, const aom_codec_enc_cfg_t *cfg) {
    return aom_codec_enc_init(ctx, aom_codec_av1_cx(), cfg, 0);
}

// Every control Droptimize sets takes an int or unsigned int, which pass the same way.
static inline aom_codec_err_t droptimize_aom_control(aom_codec_ctx_t *ctx, int id, int value) {
    return (aom_codec_control)(ctx, id, value);
}

// libaom's AV1 decoder: only the tests use it, to look at what an AV1 WebM shows. The app never
// calls it, so the linker leaves the decoder out of the app.
#include "../Vendor/libavif/include/aom/aom_decoder.h"
#include "../Vendor/libavif/include/aom/aomdx.h"

static inline aom_codec_err_t droptimize_aom_av1_decoder_init(aom_codec_ctx_t *ctx) {
    return aom_codec_dec_init(ctx, aom_codec_av1_dx(), NULL, 0);
}
