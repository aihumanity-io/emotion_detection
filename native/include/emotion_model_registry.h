#ifndef EMOTION_MODEL_REGISTRY_H_
#define EMOTION_MODEL_REGISTRY_H_

#include <map>
#include <string>

#include "emotion_sdk.h"

namespace emotion {
namespace native_sdk {

enum class ModelLifecycleState {
  kRegistered,
  kWarmed,
  kUnloaded,
};

struct RegisteredModel {
  std::string model_id;
  std::string manifest_path;
  std::string encrypted_model_path;
  emotion_runtime_preference_t runtime_preference = EMOTION_RUNTIME_DEFAULT;
  emotion_accelerator_preference_t accelerator_preference =
      EMOTION_ACCELERATOR_DEFAULT;
  ModelLifecycleState state = ModelLifecycleState::kRegistered;
};

class ModelRegistry {
 public:
  emotion_status_t register_model(const emotion_model_config_t& config);
  emotion_status_t mark_warmed(const std::string& model_id);
  emotion_status_t unload(const std::string& model_id);
  emotion_status_t remove(const std::string& model_id);
  void clear();

  const RegisteredModel* find(const std::string& model_id) const;
  size_t size() const;

 private:
  std::map<std::string, RegisteredModel> models_;
};

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_MODEL_REGISTRY_H_
