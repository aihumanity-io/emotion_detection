#include "emotion_sdk.h"

int main(void) {
  emotion_config_t config = {0};
  config.abi_version = EMOTION_SDK_ABI_VERSION;

  if (emotion_init(0) != EMOTION_STATUS_INVALID_ARGUMENT) {
    return 1;
  }
  if (emotion_init(&config) != EMOTION_STATUS_OK) {
    return 2;
  }
  if (emotion_shutdown() != EMOTION_STATUS_OK) {
    return 3;
  }
  return 0;
}
