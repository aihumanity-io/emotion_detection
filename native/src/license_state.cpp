#include "emotion_license_state.h"

namespace emotion {
namespace native_sdk {

LicenseValidationResult validate_license_state(const LicenseState& license,
                                               const std::string& model_id,
                                               int64_t now_ms) {
  LicenseValidationResult result;
  if (license.model_id.empty()) {
    result.error = "missing license model id";
    return result;
  }
  if (license.model_id != model_id) {
    result.error = "license model mismatch";
    return result;
  }
  if (license.not_before_ms > 0 && now_ms < license.not_before_ms) {
    result.error = "license not active";
    return result;
  }
  if (license.expires_at_ms > 0 && now_ms >= license.expires_at_ms) {
    result.error = "license expired";
    return result;
  }
  result.ok = true;
  return result;
}

void LicenseStore::set_license(const LicenseState& license) {
  licenses_[license.model_id] = license;
}

void LicenseStore::clear_model(const std::string& model_id) {
  licenses_.erase(model_id);
}

LicenseValidationResult LicenseStore::validate_model(
    const std::string& model_id,
    int64_t now_ms) const {
  const std::map<std::string, LicenseState>::const_iterator license_it =
      licenses_.find(model_id);
  if (license_it == licenses_.end()) {
    LicenseValidationResult result;
    result.error = "missing license";
    return result;
  }
  return validate_license_state(license_it->second, model_id, now_ms);
}

}  // namespace native_sdk
}  // namespace emotion
