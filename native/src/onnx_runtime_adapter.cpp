#include "emotion_onnx_runtime_adapter.h"

namespace emotion {
namespace native_sdk {

RuntimeLoadResult OnnxRuntimeSession::load(
    const std::vector<uint8_t>& /*model_bytes*/) {
  RuntimeLoadResult result;
  result.error = "onnx runtime adapter not linked";
  return result;
}

RuntimeLoadResult OnnxRuntimeSession::warmup() {
  RuntimeLoadResult result;
  result.error = "onnx runtime adapter not linked";
  return result;
}

RuntimePredictResult OnnxRuntimeSession::predict(const FloatTensor& /*input*/) {
  RuntimePredictResult result;
  result.error = "onnx runtime adapter not linked";
  return result;
}

void OnnxRuntimeSession::unload() {}

bool onnx_runtime_available() {
  return false;
}

}  // namespace native_sdk
}  // namespace emotion
