#include "HLS/hls.h"

component unsigned int switch_to_led(bool button_n, bool reset_button_n) {
  static bool prev_button_n = true;
  static unsigned int count = 0;

  if (!reset_button_n) {
    count = 0;
  } else if (prev_button_n && !button_n) {
    ++count;
  }

  prev_button_n = button_n;
  return count;
}
