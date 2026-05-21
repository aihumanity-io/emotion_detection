#include "emotion_file_secure_store.h"
#include "emotion_secure_store.h"

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
#define EMOTION_TEST_TMP_DIR "file_secure_store_test"
#endif

namespace {

using emotion::native_sdk::FileSecureStore;
using emotion::native_sdk::SecureStore;
using emotion::native_sdk::SecureStoreResult;

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

void set_get_and_delete_round_trip() {
  FileSecureStore file_store(test_root("round_trip"));
  const SecureStore store(file_store.adapter());
  const std::vector<uint8_t> value = {0x01u, 0x02u, 0xfeu, 0xffu};

  expect_true(file_store.is_development_fallback(),
              "file store should identify as development fallback");
  expect_true(store.available(), "file adapter should be available");
  expect_true(store.set("user-code", "david/model-a", value) ==
                  EMOTION_STATUS_OK,
              "set should succeed");

  const SecureStoreResult get_result = store.get("user-code", "david/model-a");
  expect_true(get_result.ok, "get should succeed");
  expect_true(get_result.value == value, "get should return stored bytes");

  expect_true(store.delete_value("user-code", "david/model-a") ==
                  EMOTION_STATUS_OK,
              "delete should succeed");
  expect_true(store.get("user-code", "david/model-a").status ==
                  EMOTION_STATUS_MODEL_NOT_FOUND,
              "deleted value should not be readable");
}

void namespace_and_key_values_are_path_safe() {
  FileSecureStore file_store(test_root("path_safe"));
  const SecureStore store(file_store.adapter());

  expect_true(store.set("../namespace", "model/a", {0x0au}) ==
                  EMOTION_STATUS_OK,
              "set with separators should succeed");
  expect_true(store.set("namespace", "../model/a", {0x0bu}) ==
                  EMOTION_STATUS_OK,
              "set with traversal-like key should succeed");

  expect_true(store.get("../namespace", "model/a").value ==
                  std::vector<uint8_t>{0x0au},
              "namespace with separators should be isolated");
  expect_true(store.get("namespace", "../model/a").value ==
                  std::vector<uint8_t>{0x0bu},
              "key with separators should be isolated");
}

void invalid_inputs_fail_closed() {
  FileSecureStore empty_root("");
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
  set_get_and_delete_round_trip();
  namespace_and_key_values_are_path_safe();
  invalid_inputs_fail_closed();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
