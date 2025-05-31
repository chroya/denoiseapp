#ifndef RNNOISE_H
#define RNNOISE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DenoiseState DenoiseState;

/* Create a new denoising state. You need one state per channel. */
DenoiseState *rnnoise_create(void *model);

/* Destroy an existing denoising state. */
void rnnoise_destroy(DenoiseState *st);

/* Denoise a frame of samples. */
float rnnoise_process_frame(DenoiseState *st, float *out, const float *in);

/* Get the size of a frame in samples. */
int rnnoise_get_frame_size(void);

/* Get the sample rate expected by the denoiser. */
int rnnoise_get_sample_rate(void);

/* 流式处理函数声明 - 新增 */
/* Initialize global denoise state for streaming */
int rnnoise_init_state(void);

/* Cleanup global denoise state */
void rnnoise_cleanup_state(void);

/* Process multiple frames for streaming (returns average VAD probability) */
float rnnoise_process_frames(float* output, const float* input, int num_frames);

/* File processing function for FFI */
int rnnoise(const char* infile, const char* outfile);

#ifdef __cplusplus
}
#endif

#endif 