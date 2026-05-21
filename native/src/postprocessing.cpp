#include "emotion_postprocessing.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace emotion {
namespace native_sdk {

PostprocessResult postprocess_logits(const std::vector<float>& logits,
                                     const std::vector<std::string>& labels) {
  PostprocessResult result;
  if (logits.empty()) {
    result.error = "missing logits";
    return result;
  }
  if (labels.size() != logits.size()) {
    result.error = "label count mismatch";
    return result;
  }

  const float max_logit = *std::max_element(logits.begin(), logits.end());
  std::vector<float> exp_values(logits.size(), 0.0f);
  float total = 0.0f;
  for (size_t i = 0; i < logits.size(); ++i) {
    exp_values[i] = std::exp(logits[i] - max_logit);
    total += exp_values[i];
  }
  if (total <= 0.0f) {
    result.error = "invalid logits";
    return result;
  }

  result.scores.reserve(logits.size());
  for (size_t i = 0; i < logits.size(); ++i) {
    EmotionScore score;
    score.label_index = static_cast<uint32_t>(i);
    score.label = labels[i];
    score.probability = exp_values[i] / total;
    result.scores.push_back(score);
    if (score.probability > result.top_probability || i == 0u) {
      result.top_probability = score.probability;
      result.top_label_index = score.label_index;
      result.top_label = score.label;
    }
  }

  result.ok = true;
  return result;
}

emotion_status_t copy_postprocess_to_c_result(const PostprocessResult& source,
                                              emotion_result_t* target) {
  if (target == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  target->abi_version = EMOTION_SDK_ABI_VERSION;
  target->status = source.ok ? EMOTION_STATUS_OK : EMOTION_STATUS_RUNTIME_FAILED;
  target->top_label_index = source.top_label_index;
  target->top_probability = source.top_probability;
  target->scores_count = source.scores.size();
  target->error_message[0] = '\0';
  if (!source.ok) {
    std::strncpy(target->error_message, source.error.c_str(),
                 EMOTION_SDK_ERROR_MESSAGE_SIZE - 1u);
    target->error_message[EMOTION_SDK_ERROR_MESSAGE_SIZE - 1u] = '\0';
    return target->status;
  }
  if (target->scores_capacity < source.scores.size()) {
    target->status = EMOTION_STATUS_BUFFER_TOO_SMALL;
    return target->status;
  }
  for (size_t i = 0; i < source.scores.size(); ++i) {
    target->scores[i].label_index = source.scores[i].label_index;
    target->scores[i].probability = source.scores[i].probability;
  }
  return EMOTION_STATUS_OK;
}

}  // namespace native_sdk
}  // namespace emotion
