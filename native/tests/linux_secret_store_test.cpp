#include "emotion_linux_secret_store.h"
#include "emotion_secure_store.h"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

using emotion::native_sdk::LinuxSecretStore;
using emotion::native_sdk::SecureStore;
using emotion::native_sdk::SecureStoreResult;

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

void invalid_inputs_fail_closed() {
  LinuxSecretStore linux_store;
  const SecureStore store(linux_store.adapter());

  expect_true(store.set("", "key", {0x01u}) ==
                  EMOTION_STATUS_INVALID_ARGUMENT,
              "empty namespace should fail set");
  expect_true(store.get("ns", "").status == EMOTION_STATUS_INVALID_ARGUMENT,
              "empty key should fail get");
  expect_true(store.delete_value("", "key") ==
                  EMOTION_STATUS_INVALID_ARGUMENT,
              "empty namespace should fail delete");
}

void unsupported_build_fails_closed() {
  LinuxSecretStore linux_store;
  const SecureStore store(linux_store.adapter());

  expect_true(!linux_store.is_supported(),
              "host build without libsecret should report unsupported");
  expect_true(store.available(),
              "adapter shape should remain complete without libsecret");
  expect_true(store.set("ns", "key", {0x01u}) == EMOTION_STATUS_UNSUPPORTED,
              "set should fail unsupported");
  expect_true(store.get("ns", "key").status == EMOTION_STATUS_UNSUPPORTED,
              "get should fail unsupported");
  expect_true(store.delete_value("ns", "key") == EMOTION_STATUS_UNSUPPORTED,
              "delete should fail unsupported");
}

#if defined(__linux__) && EMOTION_ENABLE_LIBSECRET

void round_trip_when_secret_service_available() {
  LinuxSecretStore linux_store;
  const SecureStore store(linux_store.adapter());
  const std::vector<uint8_t> value = {0x00u, 0x01u, 0xfeu, 0xffu};

  expect_true(linux_store.is_supported(),
              "libsecret-enabled Linux build should report supported");
  const emotion_status_t set_status =
      store.set("emotion-test", "round-trip", value);
  if (set_status == EMOTION_STATUS_RUNTIME_FAILED) {
    return;
  }

  expect_true(set_status == EMOTION_STATUS_OK, "set should succeed");
  const SecureStoreResult get_result = store.get("emotion-test", "round-trip");
  expect_true(get_result.ok, "get should succeed");
  expect_true(get_result.value == value, "get should return stored bytes");
  expect_true(store.delete_value("emotion-test", "round-trip") ==
                  EMOTION_STATUS_OK,
              "delete should succeed");
}

#endif

}  // namespace

int main() {
  invalid_inputs_fail_closed();
#if defined(__linux__) && EMOTION_ENABLE_LIBSECRET
  round_trip_when_secret_service_available();
#else
  unsupported_build_fails_closed();
#endif
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
