#ifndef EMOTION_POSTPROCESSING_H_
#define EMOTION_POSTPROCESSING_H_

#include <string>
#include <vector>

#include "emotion_sdk.h"

namespace emotion {
namespace native_sdk {

struct EmotionScore {
  uint32_t label_index = 0;
  std::string label;
  float probability = 0.0f;
};

struct PostprocessResult {
  bool ok = false;
  uint32_t top_label_index = 0;
  std::string top_label;
  float top_probability = 0.0f;
  std::vector<EmotionScore> scores;
  std::string error;
};

PostprocessResult postprocess_logits(const std::vector<float>& logits,
                                     const std::vector<std::string>& labels);

emotion_status_t copy_postprocess_to_c_result(const PostprocessResult& source,
                                              emotion_result_t* target);

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_POSTPROCESSING_H_
