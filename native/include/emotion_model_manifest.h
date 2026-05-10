#ifndef EMOTION_MODEL_MANIFEST_H_
#define EMOTION_MODEL_MANIFEST_H_

#include <cstdint>
#include <string>
#include <vector>

namespace emotion {
namespace native_sdk {

struct KdfInfo {
  std::string algorithm;
  std::string salt_b64;
  std::string info;
};

struct ModelManifest {
  int manifest_schema_version = 0;
  std::string model_id;
  std::string model_version;
  std::string model_format;
  std::vector<int64_t> input_shape;
  std::vector<std::string> labels;
  std::string aad;
  KdfInfo kdf_info;
  bool shard_required = false;
  int64_t expiry_epoch_ms = 0;
  std::string encrypted_sha256;
  std::string plaintext_sha256;
  std::string runtime_min_version;
  std::string sdk_min_version;
  std::string signature_algorithm;
};

struct ManifestParseResult {
  bool ok = false;
  ModelManifest manifest;
  std::vector<std::string> errors;
};

ManifestParseResult parse_model_manifest_json(const std::string& json_text);
ManifestParseResult parse_model_manifest_file(const std::string& path);

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_MODEL_MANIFEST_H_
