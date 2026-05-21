#include "emotion_secure_store.h"
#include "emotion_windows_secure_store.h"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#if defined(_WIN32)
#include <direct.h>
#else
#include <sys/stat.h>
#include <sys/types.h>
#endif

#ifndef EMOTION_TEST_TMP_DIR
#define EMOTION_TEST_TMP_DIR "windows_secure_store_test"
#endif

namespace {

using emotion::native_sdk::SecureStore;
using emotion::native_sdk::SecureStoreResult;
using emotion::native_sdk::WindowsSecureStore;

int g_failures = 0;

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

void make_directory(const std::string& path) {
#if defined(_WIN32)
  _mkdir(path.c_str());
#else
  mkdir(path.c_str(), 0700);
#endif
}

std::string test_root(const std::string& name) {
  const std::string root = std::string(EMOTION_TEST_TMP_DIR) + "/" + name;
  make_directory(EMOTION_TEST_TMP_DIR);
  make_directory(root);
  return root;
}

void unsupported_platform_fails_closed() {
  WindowsSecureStore windows_store(test_root("unsupported"));
  const SecureStore store(windows_store.adapter());

  expect_true(!windows_store.is_supported(),
              "non-Windows builds should report unsupported");
  expect_true(store.available(),
              "adapter shape should remain complete on every platform");
  expect_true(store.set("ns", "key", {0x01u}) == EMOTION_STATUS_UNSUPPORTED,
              "set should fail unsupported off Windows");
  expect_true(store.get("ns", "key").status == EMOTION_STATUS_UNSUPPORTED,
              "get should fail unsupported off Windows");
  expect_true(store.delete_value("ns", "key") == EMOTION_STATUS_UNSUPPORTED,
              "delete should fail unsupported off Windows");
}

#if defined(_WIN32)

void set_get_and_delete_round_trip() {
  WindowsSecureStore windows_store(test_root("round_trip"));
  const SecureStore store(windows_store.adapter());
  const std::vector<uint8_t> value = {0x10u, 0x20u, 0xfeu, 0xffu};

  expect_true(windows_store.is_supported(),
              "Windows builds should report supported");
  expect_true(store.available(), "Windows adapter should be available");
  expect_true(store.set("user-code", "david/model-a", value) ==
                  EMOTION_STATUS_OK,
              "set should protect and persist");

  const SecureStoreResult get_result = store.get("user-code", "david/model-a");
  expect_true(get_result.ok, "get should unprotect");
  expect_true(get_result.value == value, "get should return plaintext bytes");

  expect_true(store.delete_value("user-code", "david/model-a") ==
                  EMOTION_STATUS_OK,
              "delete should remove blob");
  expect_true(store.get("user-code", "david/model-a").status ==
                  EMOTION_STATUS_MODEL_NOT_FOUND,
              "deleted blob should not be readable");
}

void entropy_binds_blob_to_namespace_and_key() {
  WindowsSecureStore windows_store(test_root("entropy"));
  const SecureStore store(windows_store.adapter());

  expect_true(store.set("namespace-a", "shared-key", {0x0au}) ==
                  EMOTION_STATUS_OK,
              "namespace A set should succeed");
  expect_true(store.set("namespace-b", "shared-key", {0x0bu}) ==
                  EMOTION_STATUS_OK,
              "namespace B set should succeed");
  expect_true(store.get("namespace-a", "shared-key").value ==
                  std::vector<uint8_t>{0x0au},
              "namespace A should stay isolated");
  expect_true(store.get("namespace-b", "shared-key").value ==
                  std::vector<uint8_t>{0x0bu},
              "namespace B should stay isolated");
}

#endif

void invalid_inputs_fail_closed() {
  WindowsSecureStore empty_root("");
  const SecureStore store(empty_root.adapter());

  expect_true(store.set("ns", "key", {0x01u}) ==
                  EMOTION_STATUS_INVALID_ARGUMENT,
              "empty root should fail set");
  expect_true(store.get("ns", "key").status ==
                  EMOTION_STATUS_INVALID_ARGUMENT,
              "empty root should fail get");
  expect_true(store.delete_value("ns", "key") ==
                  EMOTION_STATUS_INVALID_ARGUMENT,
              "empty root should fail delete");
}

}  // namespace

int main() {
#if defined(_WIN32)
  set_get_and_delete_round_trip();
  entropy_binds_blob_to_namespace_and_key();
#else
  unsupported_platform_fails_closed();
#endif
  invalid_inputs_fail_closed();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
