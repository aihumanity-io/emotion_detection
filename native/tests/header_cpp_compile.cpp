#include "emotion_sdk.h"

#include <cstddef>
#include <cstdint>
#include <type_traits>

static_assert(EMOTION_SDK_ABI_VERSION == 1u, "unexpected ABI version");
static_assert(std::is_standard_layout<emotion_config_t>::value,
              "config must remain C ABI compatible");
static_assert(std::is_standard_layout<emotion_model_config_t>::value,
              "model config must remain C ABI compatible");
static_assert(std::is_standard_layout<emotion_image_t>::value,
              "image must remain C ABI compatible");
static_assert(std::is_standard_layout<emotion_result_t>::value,
              "result must remain C ABI compatible");

int main() {
  emotion_class_score_t scores[8] = {};
  emotion_result_t result = {};
  result.abi_version = EMOTION_SDK_ABI_VERSION;
  result.scores = scores;
  result.scores_capacity = sizeof(scores) / sizeof(scores[0]);
  return result.scores_capacity == 8u ? 0 : 1;
}
