#include "emotion_runtime_session.h"

namespace emotion {
namespace native_sdk {

FakeRuntimeSession::FakeRuntimeSession(const std::vector<float>& logits)
    : logits_(logits) {}

RuntimeLoadResult FakeRuntimeSession::load(const std::vector<uint8_t>& model_bytes) {
  RuntimeLoadResult result;
  if (model_bytes.empty()) {
    result.error = "missing model bytes";
    return result;
  }
  loaded_ = true;
  warmed_ = false;
  result.ok = true;
  return result;
}

RuntimeLoadResult FakeRuntimeSession::warmup() {
  RuntimeLoadResult result;
  if (!loaded_) {
    result.error = "runtime not loaded";
    return result;
  }
  warmed_ = true;
  result.ok = true;
  return result;
}

RuntimePredictResult FakeRuntimeSession::predict(const FloatTensor& input) {
  RuntimePredictResult result;
  if (!loaded_ || !warmed_) {
    result.error = "runtime not warmed";
    return result;
  }
  if (input.values.empty()) {
    result.error = "missing input tensor";
    return result;
  }
  ++predict_count_;
  result.ok = true;
  result.logits = logits_;
  return result;
}

void FakeRuntimeSession::unload() {
  loaded_ = false;
  warmed_ = false;
}

bool FakeRuntimeSession::loaded() const {
  return loaded_;
}

bool FakeRuntimeSession::warmed() const {
  return warmed_;
}

size_t FakeRuntimeSession::predict_count() const {
  return predict_count_;
}

PostprocessResult predict_and_postprocess(
    RuntimeSession* session,
    const FloatTensor& input,
    const std::vector<std::string>& labels) {
  if (session == nullptr) {
    PostprocessResult result;
    result.error = "missing runtime session";
    return result;
  }
  const RuntimePredictResult prediction = session->predict(input);
  if (!prediction.ok) {
    PostprocessResult result;
    result.error = prediction.error;
    return result;
  }
  return postprocess_logits(prediction.logits, labels);
}

}  // namespace native_sdk
}  // namespace emotion
