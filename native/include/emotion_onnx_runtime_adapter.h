#ifndef EMOTION_ONNX_RUNTIME_ADAPTER_H_
#define EMOTION_ONNX_RUNTIME_ADAPTER_H_

#include "emotion_runtime_session.h"

namespace emotion {
namespace native_sdk {

class OnnxRuntimeSession : public RuntimeSession {
 public:
  RuntimeLoadResult load(const std::vector<uint8_t>& model_bytes) override;
  RuntimeLoadResult warmup() override;
  RuntimePredictResult predict(const FloatTensor& input) override;
  void unload() override;
};

bool onnx_runtime_available();

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_ONNX_RUNTIME_ADAPTER_H_
