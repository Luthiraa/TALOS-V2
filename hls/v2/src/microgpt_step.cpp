#include "HLS/hls.h"

#include <stdint.h>

#include "../generated/microgpt_model.h"

using namespace ihc;

static const int EMBED_DIM = 16;
static const int VOCAB_SIZE = 27;
static const int HIDDEN_TILE_ROWS = 2;
struct __attribute__((packed)) StepInputs {
  uint8_t token_in;
  uint8_t pos_in;
  bool clear_cache;
  bool sample_mode;
  uint16_t temperature_q8_8;
  uint32_t rng_state_in;
};

struct __attribute__((packed)) StepOutputs {
  uint8_t next_token;
  uint8_t argmax_token;
  uint32_t rng_state_out;
  int16_t top1_logit_q11;
  uint8_t top2_token;
  int16_t top2_logit_q11;
  uint64_t logits_pack0;
  uint64_t logits_pack1;
  uint64_t logits_pack2;
  uint64_t logits_pack3;
  uint64_t logits_pack4;
  uint64_t logits_pack5;
  uint64_t logits_pack6;
};

static uint32_t xorshift32(uint32_t value) {
  value ^= value << 13;
  value ^= value >> 17;
  value ^= value << 5;
  return value;
}

static int16_t sat16(int32_t value) {
  if (value > 32767) {
    return 32767;
  }
  if (value < -32768) {
    return (int16_t)0x8000;
  }
  return (int16_t)value;
}

static int16_t scale_q16(int32_t acc, uint16_t scale) {
  int64_t prod = (int64_t)acc * (int64_t)scale;
  int64_t rounded = (prod >= 0) ? (prod + 32768) : (prod - 32768);
  return sat16((int32_t)(rounded >> 16));
}

static uint16_t exp_weight_from_delta(int32_t delta_q10) {
  if (delta_q10 >= 0) {
    return 256;
  }

  int32_t idx = (-delta_q10) >> 7;
  if (idx > 15) {
    idx = 15;
  }

  static const uint16_t lut[16] = {
      256, 181, 128, 91, 64, 45, 32, 23,
      16, 11, 8, 6, 4, 3, 2, 1};
  return lut[idx];
}

static inline int32_t dot_i8_i16(
    const int8_t weights[EMBED_DIM],
    const int16_t vec[EMBED_DIM]) {
  int32_t acc0 = 0;
  int32_t acc1 = 0;
  int32_t acc2 = 0;
  int32_t acc3 = 0;
#pragma unroll
  for (int col = 0; col < EMBED_DIM; col += 4) {
    acc0 += (int32_t)weights[col + 0] * (int32_t)vec[col + 0];
    acc1 += (int32_t)weights[col + 1] * (int32_t)vec[col + 1];
    acc2 += (int32_t)weights[col + 2] * (int32_t)vec[col + 2];
    acc3 += (int32_t)weights[col + 3] * (int32_t)vec[col + 3];
  }
  return (acc0 + acc1) + (acc2 + acc3);
}

static uint64_t pack4(const int16_t logits[VOCAB_SIZE], int base) {
  uint64_t word = 0;
#pragma unroll
  for (int i = 0; i < 4; ++i) {
    int idx = base + i;
    uint16_t lane = (idx < VOCAB_SIZE) ? (uint16_t)logits[idx] : 0;
    word |= ((uint64_t)lane) << (16 * i);
  }
  return word;
}

hls_avalon_streaming_component
component void microgpt_step(stream_in<StepInputs> &in_stream,
                             stream_out<StepOutputs> &out_stream) {
  static int16_t hidden_state[EMBED_DIM];
  StepInputs in = in_stream.read();
  StepOutputs out;

  if (in.clear_cache) {
#pragma unroll
    for (int i = 0; i < EMBED_DIM; ++i) {
      hidden_state[i] = 0;
    }
  }

  int16_t x_vec[EMBED_DIM];
  int16_t hidden_next[EMBED_DIM];
  int16_t logits[VOCAB_SIZE];

#pragma unroll
  for (int i = 0; i < EMBED_DIM; ++i) {
    int32_t value =
        (int32_t)g_wte_q[in.token_in][i] +
        (int32_t)g_wpe_q[in.pos_in][i] +
        ((int32_t)hidden_state[i] >> 1);
    x_vec[i] = sat16(value);
  }

#pragma ii 1
  for (int row_base = 0; row_base < EMBED_DIM; row_base += HIDDEN_TILE_ROWS) {
#pragma unroll
    for (int t = 0; t < HIDDEN_TILE_ROWS; ++t) {
      int row = row_base + t;
      int32_t acc = dot_i8_i16(g_wq_q[row], x_vec);
      hidden_next[row] = scale_q16(acc, g_wq_scale_q16[row]);
    }
  }

  int best_idx = 0;
  int second_idx = 1;
  int16_t best_logit = (int16_t)0x8000;
  int16_t second_logit = (int16_t)0x8000;

#pragma ii 1
  for (int row = 0; row < VOCAB_SIZE; ++row) {
    int32_t acc = dot_i8_i16(g_lm_q[row], x_vec);
    int16_t logit = scale_q16(acc, g_lm_scale_q16[row]);
    logits[row] = logit;

    if (logit > best_logit) {
      second_logit = best_logit;
      second_idx = best_idx;
      best_logit = logit;
      best_idx = row;
    } else if (logit > second_logit) {
      second_logit = logit;
      second_idx = row;
    }
  }

  out.rng_state_out = xorshift32(in.rng_state_in);

  uint16_t sample_temp = in.temperature_q8_8;
  uint8_t sample_choice = (uint8_t)best_idx;
  bool sample_found = false;
  uint32_t sample_rng = out.rng_state_out;
  int sample_shift = 0;
  if (sample_temp <= 128) {
    sample_shift = 1;
  } else if (sample_temp > 512) {
    sample_shift = -2;
  } else if (sample_temp > 256) {
    sample_shift = -1;
  }

#pragma unroll
  for (int i = 0; i < 4; ++i) {
    uint8_t sample_candidate = (uint8_t)(sample_rng & 31);
    if (sample_candidate >= VOCAB_SIZE) {
      sample_candidate = (uint8_t)(sample_candidate - VOCAB_SIZE);
    }

    int32_t sample_delta =
        (int32_t)logits[sample_candidate] - (int32_t)best_logit;

    if (sample_shift > 0) {
      sample_delta <<= sample_shift;
    } else if (sample_shift < 0) {
      sample_delta >>= -sample_shift;
    }

    uint16_t sample_weight = exp_weight_from_delta(sample_delta);
    if (!sample_found && ((uint16_t)((sample_rng >> 8) & 0xFF) < sample_weight)) {
      sample_choice = sample_candidate;
      sample_found = true;
    }

    sample_rng = xorshift32(sample_rng);
  }

#pragma unroll
  for (int i = 0; i < EMBED_DIM; ++i) {
    hidden_state[i] = hidden_next[i];
  }

  out.argmax_token = (uint8_t)best_idx;
  out.next_token = in.sample_mode ? sample_choice : (uint8_t)best_idx;
  out.top1_logit_q11 = best_logit;
  out.top2_token = (uint8_t)second_idx;
  out.top2_logit_q11 = second_logit;

  out.logits_pack0 = pack4(logits, 0);
  out.logits_pack1 = pack4(logits, 4);
  out.logits_pack2 = pack4(logits, 8);
  out.logits_pack3 = pack4(logits, 12);
  out.logits_pack4 = pack4(logits, 16);
  out.logits_pack5 = pack4(logits, 20);
  out.logits_pack6 = pack4(logits, 24);
  out_stream.write(out);
}
