#include "emotion_secure_store.h"

#include <cstdlib>
#include <cstring>
#include <iostream>
#include <map>
#include <string>
#include <vector>

namespace {

using emotion::native_sdk::SecureStore;
using emotion::native_sdk::SecureStoreResult;

int g_failures = 0;

struct MockStore {
  std::map<std::string, std::vector<uint8_t>> values;
};

void expect_true(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << std::endl;
    ++g_failures;
  }
}

std::string storage_key(const char* namespace_id, const char* key) {
  return std::string(namespace_id) + "\n" + key;
}

emotion_status_t mock_get(const char* namespace_id,
                          const char* key,
                          uint8_t* out_value,
                          size_t* in_out_value_len,
                          void* user_data) {
  MockStore* store = static_cast<MockStore*>(user_data);
  const std::map<std::string, std::vector<uint8_t>>::const_iterator it =
      store->values.find(storage_key(namespace_id, key));
  if (it == store->values.end()) {
    return EMOTION_STATUS_MODEL_NOT_FOUND;
  }
  if (in_out_value_len == nullptr) {
    return EMOTION_STATUS_INVALID_ARGUMENT;
  }
  if (out_value == nullptr || *in_out_value_len < it->second.size()) {
    *in_out_value_len = it->second.size();
    return EMOTION_STATUS_BUFFER_TOO_SMALL;
  }
  std::memcpy(out_value, it->second.data(), it->second.size());
  *in_out_value_len = it->second.size();
  return EMOTION_STATUS_OK;
}

emotion_status_t mock_set(const char* namespace_id,
                          const char* key,
                          const uint8_t* value,
                          size_t value_len,
                          void* user_data) {
  MockStore* store = static_cast<MockStore*>(user_data);
  store->values[storage_key(namespace_id, key)] =
      std::vector<uint8_t>(value, value + value_len);
  return EMOTION_STATUS_OK;
}

emotion_status_t mock_delete(const char* namespace_id,
                             const char* key,
                             void* user_data) {
  MockStore* store = static_cast<MockStore*>(user_data);
  store->values.erase(storage_key(namespace_id, key));
  return EMOTION_STATUS_OK;
}

emotion_secure_store_adapter_t adapter_for(MockStore* store) {
  emotion_secure_store_adapter_t adapter = {};
  adapter.abi_version = EMOTION_SDK_ABI_VERSION;
  adapter.get = mock_get;
  adapter.set = mock_set;
  adapter.delete_value = mock_delete;
  adapter.user_data = store;
  return adapter;
}

void set_get_and_delete_round_trip() {
  MockStore mock;
  const emotion_secure_store_adapter_t adapter = adapter_for(&mock);
  const SecureStore store(&adapter);
  const std::vector<uint8_t> value = {1u, 2u, 3u, 4u};

  expect_true(store.available(), "complete adapter should be available");
  expect_true(store.set("user-code", "david/model-a", value) ==
                  EMOTION_STATUS_OK,
              "set should succeed");

  const SecureStoreResult get_result = store.get("user-code", "david/model-a");
  expect_true(get_result.ok, "get should succeed");
  expect_true(get_result.value == value, "get should return stored value");

  expect_true(store.delete_value("user-code", "david/model-a") ==
                  EMOTION_STATUS_OK,
              "delete should succeed");
  expect_true(!store.get("user-code", "david/model-a").ok,
              "deleted value should not be readable");
}

void namespace_isolation_is_preserved() {
  MockStore mock;
  const emotion_secure_store_adapter_t adapter = adapter_for(&mock);
  const SecureStore store(&adapter);

  store.set("namespace-a", "shared-key", {0x0au});
  store.set("namespace-b", "shared-key", {0x0bu});

  expect_true(store.get("namespace-a", "shared-key").value ==
                  std::vector<uint8_t>{0x0au},
              "namespace A value should stay isolated");
  expect_true(store.get("namespace-b", "shared-key").value ==
                  std::vector<uint8_t>{0x0bu},
              "namespace B value should stay isolated");
}

void incomplete_adapter_fails_closed() {
  emotion_secure_store_adapter_t adapter = {};
  adapter.abi_version = EMOTION_SDK_ABI_VERSION;
  const SecureStore store(&adapter);

  expect_true(!store.available(), "incomplete adapter should not be available");
  expect_true(store.set("ns", "key", {1u}) == EMOTION_STATUS_INVALID_ARGUMENT,
              "set should fail without callbacks");
  expect_true(store.get("ns", "key").status == EMOTION_STATUS_INVALID_ARGUMENT,
              "get should fail without callbacks");
  expect_true(store.delete_value("ns", "key") ==
                  EMOTION_STATUS_INVALID_ARGUMENT,
              "delete should fail without callbacks");
}

}  // namespace

int main() {
  set_get_and_delete_round_trip();
  namespace_isolation_is_preserved();
  incomplete_adapter_fails_closed();
  return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
