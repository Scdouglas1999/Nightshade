#include "libraw_types.h"

typedef struct nightshade_libraw_config_t {
    int white_balance_mode;
    float user_mul[4];
    int output_color;
    int output_bps;
    int user_qual;
    int highlight;
    float bright;
    int no_auto_bright;
    int half_size;
    const char *bad_pixels;
    const char *dark_frame;
    int user_sat;
    int has_user_sat;
    double gamma[2];
    int has_gamma;
    double chromatic_aberration[2];
    int has_chromatic_aberration;
    unsigned max_memory_mb;
    int has_max_memory_mb;
} nightshade_libraw_config_t;

void nightshade_libraw_apply_config(
    libraw_data_t *processor,
    const nightshade_libraw_config_t *config
) {
    if (!processor || !config) {
        return;
    }

    processor->params.use_camera_wb = 0;
    processor->params.use_auto_wb = 0;

    switch (config->white_balance_mode) {
    case 0:
        processor->params.use_camera_wb = 1;
        break;
    case 1:
        processor->params.use_auto_wb = 1;
        break;
    case 2:
        processor->params.user_mul[0] = config->user_mul[0];
        processor->params.user_mul[1] = config->user_mul[1];
        processor->params.user_mul[2] = config->user_mul[2];
        processor->params.user_mul[3] = config->user_mul[3];
        break;
    default:
        break;
    }

    processor->params.output_color = config->output_color;
    processor->params.output_bps = config->output_bps;
    processor->params.user_qual = config->user_qual;
    processor->params.highlight = config->highlight;
    processor->params.bright = config->bright;
    processor->params.no_auto_bright = config->no_auto_bright;
    processor->params.half_size = config->half_size;
    processor->params.bad_pixels = (char *)config->bad_pixels;
    processor->params.dark_frame = (char *)config->dark_frame;

    if (config->has_user_sat) {
        processor->params.user_sat = config->user_sat;
    }

    if (config->has_gamma) {
        processor->params.gamm[0] = config->gamma[0];
        processor->params.gamm[1] = config->gamma[1];
    }

    if (config->has_chromatic_aberration) {
        processor->params.aber[0] = config->chromatic_aberration[0];
        processor->params.aber[1] = 1.0;
        processor->params.aber[2] = config->chromatic_aberration[1];
        processor->params.aber[3] = 1.0;
    }

    if (config->has_max_memory_mb) {
        processor->rawparams.max_raw_memory_mb = config->max_memory_mb;
    }
}
