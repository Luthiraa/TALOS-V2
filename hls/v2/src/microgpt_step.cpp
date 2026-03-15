#include "HLS/hls.h"

#include <stdint.h>

#include "../generated/microgpt_model.h"

static const uint16_t k_exp_lut_q8[16] = {
    256, 181, 128, 91, 64, 45, 32, 23,
    16, 11, 8, 6, 4, 3, 2, 1
};

static int16_t sat16(int32_t value) {
  if (value > 32767) {
    return 32767;
  }
  if (value < -32768) {
    return -32768;
  }
  return (int16_t)value;
}

static uint32_t xorshift32(uint32_t state) {
  state ^= state << 13;
  state ^= state >> 17;
  state ^= state << 5;
  return state;
}

static int16_t abs16(int16_t value) {
  return (value < 0) ? (int16_t)(-value) : value;
}

// Cheap magnitude normalization keeps the vector in a stable Q5.11 range
// without introducing floating-point sqrt/divide hardware.
static void rmsnorm_inplace(int16_t x[MGPT_EMBED_DIM]) {
  int16_t max_abs = 1;
  for (int i = 0; i < MGPT_EMBED_DIM; ++i) {
    int16_t ax = abs16(x[i]);
    if (ax > max_abs) {
      max_abs = ax;
    }
  }

  int shift = 0;
  if (max_abs > MGPT_ACT_SCALE) {
    while ((max_abs > MGPT_ACT_SCALE) && (shift < 4)) {
      max_abs >>= 1;
      ++shift;
    }
    for (int i = 0; i < MGPT_EMBED_DIM; ++i) {
      x[i] = x[i] >> shift;
    }
  } else if (max_abs < (MGPT_ACT_SCALE >> 1)) {
    while ((max_abs < (MGPT_ACT_SCALE >> 1)) && (shift < 2)) {
      max_abs <<= 1;
      ++shift;
    }
    for (int i = 0; i < MGPT_EMBED_DIM; ++i) {
      x[i] = sat16((int32_t)x[i] << shift);
    }
  }
}

static void matvec_i8_i16(const int8_t weight[][MGPT_EMBED_DIM],
                          const uint16_t scale_q16[],
                          const int16_t x[MGPT_EMBED_DIM],
                          int16_t out[MGPT_EMBED_DIM]) {
  for (int row = 0; row < MGPT_EMBED_DIM; ++row) {
    int32_t acc = 0;
    for (int col = 0; col < MGPT_EMBED_DIM; ++col) {
      acc += (int32_t)weight[row][col] * (int32_t)x[col];
    }
    out[row] = sat16((acc * (int32_t)scale_q16[row] + (1 << 15)) >> 16);
  }
}

static void matvec_fc1(const int16_t x[MGPT_EMBED_DIM], int16_t out[MGPT_MLP_DIM]) {
  for (int row = 0; row < MGPT_MLP_DIM; ++row) {
    int32_t acc = 0;
    for (int col = 0; col < MGPT_EMBED_DIM; ++col) {
      acc += (int32_t)g_fc1_q[row][col] * (int32_t)x[col];
    }
    out[row] = sat16((acc * (int32_t)g_fc1_scale_q16[row] + (1 << 15)) >> 16);
  }
}

static void matvec_fc2(const int16_t x[MGPT_MLP_DIM], int16_t out[MGPT_EMBED_DIM]) {
  for (int row = 0; row < MGPT_EMBED_DIM; ++row) {
    int32_t acc = 0;
    for (int col = 0; col < MGPT_MLP_DIM; ++col) {
      acc += (int32_t)g_fc2_q[row][col] * (int32_t)x[col];
    }
    out[row] = sat16((acc * (int32_t)g_fc2_scale_q16[row] + (1 << 15)) >> 16);
  }
}

static void logits_head(const int16_t x[MGPT_EMBED_DIM], int16_t logits[MGPT_VOCAB_SIZE]) {
  for (int row = 0; row < MGPT_VOCAB_SIZE; ++row) {
    int32_t acc = 0;
    for (int col = 0; col < MGPT_EMBED_DIM; ++col) {
      acc += (int32_t)g_lm_q[row][col] * (int32_t)x[col];
    }
    logits[row] = sat16((acc * (int32_t)g_lm_scale_q16[row] + (1 << 15)) >> 16);
  }
}

static uint16_t exp_weight_from_delta(int32_t delta_q10) {
  if (delta_q10 >= 0) {
    return k_exp_lut_q8[0];
  }
  int32_t idx = (-delta_q10) >> 7;
  if (idx > 15) {
    idx = 15;
  }
  return k_exp_lut_q8[idx];
}

static uint64_t pack4(const int16_t logits[MGPT_VOCAB_SIZE], int base) {
  uint64_t word = 0;
  for (int i = 0; i < 4; ++i) {
    int idx = base + i;
    uint16_t lane = (idx < MGPT_VOCAB_SIZE) ? (uint16_t)logits[idx] : 0;
    word |= ((uint64_t)lane) << (16 * i);
  }
  return word;
}

component void microgpt_step(
    unsigned char token_in,
    unsigned char pos_in,
    bool clear_cache,
    bool sample_mode,
    unsigned short temperature_q8_8,
    unsigned int rng_state_in,
    unsigned char &next_token,
    unsigned char &argmax_token,
    unsigned int &rng_state_out,
    short &top1_logit_q11,
    unsigned char &top2_token,
    short &top2_logit_q11,
    unsigned long long &logits_pack0,
    unsigned long long &logits_pack1,
    unsigned long long &logits_pack2,
    unsigned long long &logits_pack3,
    unsigned long long &logits_pack4,
    unsigned long long &logits_pack5,
    unsigned long long &logits_pack6) {
  static int16_t k_cache[MGPT_CONTEXT_LEN][MGPT_EMBED_DIM];
  static int16_t v_cache[MGPT_CONTEXT_LEN][MGPT_EMBED_DIM];

  if (clear_cache) {
    for (int t = 0; t < MGPT_CONTEXT_LEN; ++t) {
      for (int d = 0; d < MGPT_EMBED_DIM; ++d) {
        k_cache[t][d] = 0;
        v_cache[t][d] = 0;
      }
    }
  }

  int16_t x[MGPT_EMBED_DIM];
  for (int i = 0; i < MGPT_EMBED_DIM; ++i) {
    x[i] = sat16((int32_t)g_wte_q[token_in][i] + (int32_t)g_wpe_q[pos_in][i]);
  }
  rmsnorm_inplace(x);

  int16_t norm1[MGPT_EMBED_DIM];
  for (int i = 0; i < MGPT_EMBED_DIM; ++i) {
    norm1[i] = x[i];
  }
  rmsnorm_inplace(norm1);

  int16_t q_q11[MGPT_EMBED_DIM];
  int16_t k_q11[MGPT_EMBED_DIM];
  int16_t v_q11[MGPT_EMBED_DIM];
  matvec_i8_i16(g_wq_q, g_wq_scale_q16, norm1, q_q11);
  matvec_i8_i16(g_wk_q, g_wk_scale_q16, norm1, k_q11);
  matvec_i8_i16(g_wv_q, g_wv_scale_q16, norm1, v_q11);

  for (int d = 0; d < MGPT_EMBED_DIM; ++d) {
    k_cache[pos_in][d] = k_q11[d];
    v_cache[pos_in][d] = v_q11[d];
  }

  int16_t attn_ctx_q11[MGPT_EMBED_DIM];
  for (int i = 0; i < MGPT_EMBED_DIM; ++i) {
    attn_ctx_q11[i] = 0;
  }

  for (int h = 0; h < MGPT_NUM_HEADS; ++h) {
    int32_t scores_q10[MGPT_CONTEXT_LEN];
    uint16_t weights_q8[MGPT_CONTEXT_LEN];
    int32_t max_score = -(1 << 30);
    int base = h * MGPT_HEAD_DIM;

    for (int t = 0; t <= pos_in; ++t) {
      int32_t dot = 0;
      for (int d = 0; d < MGPT_HEAD_DIM; ++d) {
        dot += (int32_t)q_q11[base + d] * (int32_t)k_cache[t][base + d];
      }
      scores_q10[t] = dot >> (MGPT_ACT_FRAC_BITS + 1);
      if (scores_q10[t] > max_score) {
        max_score = scores_q10[t];
      }
    }

    uint32_t denom = 0;
    for (int t = 0; t <= pos_in; ++t) {
      weights_q8[t] = exp_weight_from_delta(scores_q10[t] - max_score);
      denom += weights_q8[t];
    }
    if (denom == 0) {
      denom = 1;
    }

    for (int d = 0; d < MGPT_HEAD_DIM; ++d) {
      int32_t acc = 0;
      for (int t = 0; t <= pos_in; ++t) {
        acc += (int32_t)weights_q8[t] * (int32_t)v_cache[t][base + d];
      }
      attn_ctx_q11[base + d] = sat16((acc + ((int32_t)denom >> 1)) / (int32_t)denom);
    }
  }

  int16_t attn_out_q11[MGPT_EMBED_DIM];
  matvec_i8_i16(g_wo_q, g_wo_scale_q16, attn_ctx_q11, attn_out_q11);
  for (int i = 0; i < MGPT_EMBED_DIM; ++i) {
    x[i] = sat16((int32_t)x[i] + (int32_t)attn_out_q11[i]);
  }

  int16_t norm2[MGPT_EMBED_DIM];
  for (int i = 0; i < MGPT_EMBED_DIM; ++i) {
    norm2[i] = x[i];
  }
  rmsnorm_inplace(norm2);

  int16_t hidden_q11[MGPT_MLP_DIM];
  int16_t mlp_out_q11[MGPT_EMBED_DIM];
  matvec_fc1(norm2, hidden_q11);
  for (int i = 0; i < MGPT_MLP_DIM; ++i) {
    int32_t v = hidden_q11[i];
    if (v < 0) {
      v = 0;
    }
    hidden_q11[i] = sat16((v * v + (MGPT_ACT_SCALE >> 1)) >> MGPT_ACT_FRAC_BITS);
  }
  matvec_fc2(hidden_q11, mlp_out_q11);
  for (int i = 0; i < MGPT_EMBED_DIM; ++i) {
    x[i] = sat16((int32_t)x[i] + (int32_t)mlp_out_q11[i]);
  }

  int16_t logits_q11[MGPT_VOCAB_SIZE];
  logits_head(x, logits_q11);

  int best = 0;
  int second = 1;
  if (logits_q11[second] > logits_q11[best]) {
    best = 1;
    second = 0;
  }
  for (int i = 2; i < MGPT_VOCAB_SIZE; ++i) {
    if (logits_q11[i] > logits_q11[best]) {
      second = best;
      best = i;
    } else if (logits_q11[i] > logits_q11[second]) {
      second = i;
    }
  }

  argmax_token = (unsigned char)best;
  top1_logit_q11 = logits_q11[best];
  top2_token = (unsigned char)second;
  top2_logit_q11 = logits_q11[second];

  (void)sample_mode;
  (void)temperature_q8_8;
  rng_state_out = xorshift32(rng_state_in);
  next_token = (argmax_token == BOS_TOKEN) ? top2_token : argmax_token;

  logits_pack0 = pack4(logits_q11, 0);
  logits_pack1 = pack4(logits_q11, 4);
  logits_pack2 = pack4(logits_q11, 8);
  logits_pack3 = pack4(logits_q11, 12);
  logits_pack4 = pack4(logits_q11, 16);
  logits_pack5 = pack4(logits_q11, 20);
  logits_pack6 = pack4(logits_q11, 24);
}
