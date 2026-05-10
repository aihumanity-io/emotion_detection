#ifndef EMOTION_PREPROCESSING_H_
#define EMOTION_PREPROCESSING_H_

#include <string>

#include "emotion_sdk.h"
#include "emotion_tensor.h"

namespace emotion {
namespace native_sdk {

struct PreprocessOptions {
  uint32_t target_width = 0;
  uint32_t target_height = 0;
  TensorLayout layout = TensorLayout::kNhwc;
  float scale = 1.0f / 255.0f;
  float mean[3] = {0.0f, 0.0f, 0.0f};
  float stddev[3] = {1.0f, 1.0f, 1.0f};
};

struct PreprocessResult {
  bool ok = false;
  FloatTensor tensor;
  std::string error;
};

PreprocessResult preprocess_image(const emotion_image_t& image,
                                  const emotion_face_box_t* face_box,
                                  const PreprocessOptions& options);

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_PREPROCESSING_H_
