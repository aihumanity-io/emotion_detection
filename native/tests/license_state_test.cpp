#include "emotion_license_state.h"

#include <cstdlib>
#include <iostream>
#include <string>

namespace {

using emotion::native_sdk::LicenseState;
using emotion::native_sdk::LicenseStore;
using emotion::native_sdk::LicenseValidationResult;
using emotion::native_sdk::validate_license_state;

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

LicenseState active_license() {
  LicenseState license;
  license.model_id = "aih_fer2025";
  license.not_before_ms = 1000;
  license.expires_at_ms = 5000;
  return license;
}

void active_license_validates() {
  const LicenseValidationResult result =
      validate_license_state(active_license(), "aih_fer2025", 2000);

  expect_true(result.ok, "active license should validate");
}

void not_before_is_enforced() {
  const LicenseValidationResult result =
      validate_license_state(active_license(), "aih_fer2025", 999);

  expect_true(!result.ok, "early license should fail");
  expect_true(result.error == "license not active",
              "not active error should be reported");
}

void expiry_is_enforced() {
  const LicenseValidationResult result =
      validate_license_state(active_license(), "aih_fer2025", 5000);

  expect_true(!result.ok, "expired license should fail");
  expect_true(result.error == "license expired",
              "expired error should be reported");
}

void model_mismatch_is_rejected() {
  const LicenseValidationResult result =
      validate_license_state(active_license(), "other_model", 2000);

  expect_true(!result.ok, "model mismatch should fail");
  expect_true(result.error == "license model mismatch",
              "model mismatch error should be reported");
}

void store_validates_by_model_id() {
  LicenseStore store;
  store.set_license(active_license());

  const LicenseValidationResult found =
      store.validate_model("aih_fer2025", 2000);
  const LicenseValidationResult missing = store.validate_model("missing", 2000);

  expect_true(found.ok, "stored license should validate");
  expect_true(!missing.ok, "missing license should fail");
  expect_true(missing.error == "missing license",
              "missing license error should be reported");
}

void clear_model_removes_license() {
  LicenseStore store;
  store.set_license(active_license());
  store.clear_model("aih_fer2025");

  const LicenseValidationResult result =
      store.validate_model("aih_fer2025", 2000);

  expect_true(!result.ok, "cleared license should fail");
  expect_true(result.error == "missing license",
              "cleared model should report missing license");
}

}  // namespace

int main() {
  active_license_validates();
  not_before_is_enforced();
  expiry_is_enforced();
  model_mismatch_is_rejected();
  store_validates_by_model_id();
  clear_model_removes_license();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
