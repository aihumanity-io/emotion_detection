#include "emotion_model_manifest.h"

#include <fstream>
#include <regex>
#include <sstream>

#include <nlohmann/json.hpp>

namespace emotion {
namespace native_sdk {
namespace {

using Json = nlohmann::json;

const int kCurrentSchemaVersion = 1;

bool is_hex_sha256(const std::string& value) {
  static const std::regex pattern("^[0-9a-f]{64}$");
  return std::regex_match(value, pattern);
}

bool has_field(const Json& root,
               const char* field,
               std::vector<std::string>* errors) {
  if (!root.contains(field)) {
    errors->push_back(std::string("missing ") + field);
    return false;
  }
  return true;
}

bool read_string(const Json& root,
                 const char* field,
                 std::string* output,
                 std::vector<std::string>* errors) {
  if (!has_field(root, field, errors)) {
    return false;
  }
  if (!root[field].is_string() || root[field].get<std::string>().empty()) {
    errors->push_back(std::string("invalid ") + field);
    return false;
  }
  *output = root[field].get<std::string>();
  return true;
}

bool read_int64(const Json& root,
                const char* field,
                int64_t* output,
                std::vector<std::string>* errors) {
  if (!has_field(root, field, errors)) {
    return false;
  }
  if (!root[field].is_number_integer()) {
    errors->push_back(std::string("invalid ") + field);
    return false;
  }
  *output = root[field].get<int64_t>();
  return true;
}

bool read_bool(const Json& root,
               const char* field,
               bool* output,
               std::vector<std::string>* errors) {
  if (!has_field(root, field, errors)) {
    return false;
  }
  if (!root[field].is_boolean()) {
    errors->push_back(std::string("invalid ") + field);
    return false;
  }
  *output = root[field].get<bool>();
  return true;
}

void read_input_shape(const Json& root,
                      std::vector<int64_t>* output,
                      std::vector<std::string>* errors) {
  if (!has_field(root, "input_shape", errors)) {
    return;
  }
  if (!root["input_shape"].is_array() || root["input_shape"].empty()) {
    errors->push_back("invalid input_shape");
    return;
  }
  for (const Json& dimension : root["input_shape"]) {
    if (!dimension.is_number_integer() || dimension.get<int64_t>() <= 0) {
      errors->push_back("invalid input_shape");
      return;
    }
    output->push_back(dimension.get<int64_t>());
  }
}

void read_labels(const Json& root,
                 std::vector<std::string>* output,
                 std::vector<std::string>* errors) {
  if (!has_field(root, "labels", errors)) {
    return;
  }
  if (!root["labels"].is_array() || root["labels"].empty()) {
    errors->push_back("invalid labels");
    return;
  }
  for (const Json& label : root["labels"]) {
    if (!label.is_string() || label.get<std::string>().empty()) {
      errors->push_back("invalid labels");
      return;
    }
    output->push_back(label.get<std::string>());
  }
}

void read_kdf_info(const Json& root,
                   KdfInfo* output,
                   std::vector<std::string>* errors) {
  if (!has_field(root, "kdf_info", errors)) {
    return;
  }
  if (!root["kdf_info"].is_object()) {
    errors->push_back("invalid kdf_info");
    return;
  }
  const Json& kdf_info = root["kdf_info"];
  read_string(kdf_info, "algorithm", &output->algorithm, errors);
  read_string(kdf_info, "salt_b64", &output->salt_b64, errors);
  read_string(kdf_info, "info", &output->info, errors);
  if (!output->algorithm.empty() && output->algorithm != "hkdf-sha256") {
    errors->push_back("unsupported kdf_info.algorithm");
  }
}

void validate_hash(const char* field,
                   const std::string& value,
                   std::vector<std::string>* errors) {
  if (!value.empty() && !is_hex_sha256(value)) {
    errors->push_back(std::string("invalid ") + field);
  }
}

}  // namespace

ManifestParseResult parse_model_manifest_json(const std::string& json_text) {
  ManifestParseResult result;
  Json root;
  try {
    root = Json::parse(json_text);
  } catch (const Json::parse_error& error) {
    result.errors.push_back(std::string("invalid json: ") + error.what());
    return result;
  }

  if (!root.is_object()) {
    result.errors.push_back("manifest must be a JSON object");
    return result;
  }

  ModelManifest manifest;
  int64_t schema_version = 0;
  read_int64(root, "manifest_schema_version", &schema_version, &result.errors);
  manifest.manifest_schema_version = static_cast<int>(schema_version);
  if (schema_version != 0 && schema_version != kCurrentSchemaVersion) {
    result.errors.push_back("unsupported manifest_schema_version");
  }

  read_string(root, "model_id", &manifest.model_id, &result.errors);
  read_string(root, "model_version", &manifest.model_version, &result.errors);
  read_string(root, "model_format", &manifest.model_format, &result.errors);
  if (!manifest.model_format.empty() && manifest.model_format != "onnx") {
    result.errors.push_back("unsupported model_format");
  }
  read_input_shape(root, &manifest.input_shape, &result.errors);
  read_labels(root, &manifest.labels, &result.errors);
  read_string(root, "aad", &manifest.aad, &result.errors);
  read_kdf_info(root, &manifest.kdf_info, &result.errors);
  read_bool(root, "shard_required", &manifest.shard_required, &result.errors);
  read_int64(root, "expiry_epoch_ms", &manifest.expiry_epoch_ms,
             &result.errors);
  read_string(root, "encrypted_sha256", &manifest.encrypted_sha256,
              &result.errors);
  read_string(root, "plaintext_sha256", &manifest.plaintext_sha256,
              &result.errors);
  read_string(root, "runtime_min_version", &manifest.runtime_min_version,
              &result.errors);
  read_string(root, "sdk_min_version", &manifest.sdk_min_version,
              &result.errors);
  read_string(root, "signature_algorithm", &manifest.signature_algorithm,
              &result.errors);

  validate_hash("encrypted_sha256", manifest.encrypted_sha256, &result.errors);
  validate_hash("plaintext_sha256", manifest.plaintext_sha256, &result.errors);

  result.ok = result.errors.empty();
  result.manifest = manifest;
  return result;
}

ManifestParseResult parse_model_manifest_file(const std::string& path) {
  std::ifstream input(path.c_str(), std::ios::in | std::ios::binary);
  if (!input) {
    ManifestParseResult result;
    result.errors.push_back("manifest file not readable");
    return result;
  }

  std::ostringstream buffer;
  buffer << input.rdbuf();
  return parse_model_manifest_json(buffer.str());
}

}  // namespace native_sdk
}  // namespace emotion
