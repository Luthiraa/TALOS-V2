#include "HLS/hls.h"

component unsigned int switch_to_led(bool key0_n, bool key1_n) {
  const unsigned int debounce_clks = 500000;

  static bool stable0 = true;
  static bool stable1 = true;
  static bool prev0 = true;
  static unsigned int debounce0 = 0;
  static unsigned int debounce1 = 0;
  static unsigned int count = 0;

  if (key0_n == stable0) {
    debounce0 = 0;
  } else if (debounce0 >= (debounce_clks - 1)) {
    stable0 = key0_n;
    debounce0 = 0;
  } else {
    ++debounce0;
  }

  if (key1_n == stable1) {
    debounce1 = 0;
  } else if (debounce1 >= (debounce_clks - 1)) {
    stable1 = key1_n;
    debounce1 = 0;
  } else {
    ++debounce1;
  }

  if (!stable1) {
    count = 0;
  } else if (prev0 && !stable0) {
    ++count;
  }

  prev0 = stable0;
  return count;
}
