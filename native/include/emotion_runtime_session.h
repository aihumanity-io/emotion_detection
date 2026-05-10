#ifndef EMOTION_RUNTIME_SESSION_H_
#define EMOTION_RUNTIME_SESSION_H_

#include <string>
#include <vector>

#include "emotion_postprocessing.h"
#include "emotion_tensor.h"

namespace emotion {
namespace native_sdk {

struct RuntimeLoadResult {
  bool ok = false;
  std::string error;
};

struct RuntimePredictResult {
  bool ok = false;
  std::vector<float> logits;
  std::string error;
};

class RuntimeSession {
 public:
  virtual ~RuntimeSession() {}

  virtual RuntimeLoadResult load(const std::vector<uint8_t>& model_bytes) = 0;
  virtual RuntimeLoadResult warmup() = 0;
  virtual RuntimePredictResult predict(const FloatTensor& input) = 0;
  virtual void unload() = 0;
};

class FakeRuntimeSession : public RuntimeSession {
 public:
  explicit FakeRuntimeSession(const std::vector<float>& logits);

  RuntimeLoadResult load(const std::vector<uint8_t>& model_bytes) override;
  RuntimeLoadResult warmup() override;
  RuntimePredictResult predict(const FloatTensor& input) override;
  void unload() override;

  bool loaded() const;
  bool warmed() const;
  size_t predict_count() const;

 private:
  std::vector<float> logits_;
  bool loaded_ = false;
  bool warmed_ = false;
  size_t predict_count_ = 0;
};

PostprocessResult predict_and_postprocess(RuntimeSession* session,
                                          const FloatTensor& input,
                                          const std::vector<std::string>& labels);

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_RUNTIME_SESSION_H_
