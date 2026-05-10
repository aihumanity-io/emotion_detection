#ifndef EMOTION_TENSOR_H_
#define EMOTION_TENSOR_H_

#include <cstdint>
#include <vector>

namespace emotion {
namespace native_sdk {

enum class TensorLayout {
  kNhwc,
  kNchw,
};

struct FloatTensor {
  std::vector<int64_t> shape;
  TensorLayout layout = TensorLayout::kNhwc;
  std::vector<float> values;
};

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_TENSOR_H_
