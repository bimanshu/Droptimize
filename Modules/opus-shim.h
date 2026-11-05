// libopus for Swift. Its settings go through a C variadic function, which Swift can't call, so
// these small wrappers do it from C.
#include "../Vendor/libopus/include/opus/opus.h"

static inline int droptimize_opus_set_bitrate(OpusEncoder *encoder, opus_int32 bitsPerSecond) {
    return opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitsPerSecond));
}

// Samples the encoder delays its output by; the decoder skips them ("pre-skip").
static inline opus_int32 droptimize_opus_lookahead(OpusEncoder *encoder) {
    opus_int32 samples = 0;
    opus_encoder_ctl(encoder, OPUS_GET_LOOKAHEAD(&samples));
    return samples;
}
