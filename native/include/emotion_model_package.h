#ifndef EMOTION_MODEL_PACKAGE_H_
#define EMOTION_MODEL_PACKAGE_H_

#include <string>

#include "emotion_logging.h"
#include "emotion_model_manifest.h"

namespace emotion {
namespace native_sdk {

struct ModelPackageVerificationResult {
  bool ok = false;
  std::string error;
};

ModelPackageVerificationResult verify_model_package(
    const ModelManifest& manifest,
    const std::string& encrypted_model_path,
    int64_t now_ms,
    const NativeLogger* logger);

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_MODEL_PACKAGE_H_
