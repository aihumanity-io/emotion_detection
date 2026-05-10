#ifndef EMOTION_LICENSE_STATE_H_
#define EMOTION_LICENSE_STATE_H_

#include <cstdint>
#include <map>
#include <string>

namespace emotion {
namespace native_sdk {

struct LicenseState {
  std::string model_id;
  int64_t not_before_ms = 0;
  int64_t expires_at_ms = 0;
};

struct LicenseValidationResult {
  bool ok = false;
  std::string error;
};

LicenseValidationResult validate_license_state(const LicenseState& license,
                                               const std::string& model_id,
                                               int64_t now_ms);

class LicenseStore {
 public:
  void set_license(const LicenseState& license);
  void clear_model(const std::string& model_id);

  LicenseValidationResult validate_model(const std::string& model_id,
                                         int64_t now_ms) const;

 private:
  std::map<std::string, LicenseState> licenses_;
};

}  // namespace native_sdk
}  // namespace emotion

#endif  // EMOTION_LICENSE_STATE_H_
