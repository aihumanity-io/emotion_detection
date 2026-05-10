cmake_minimum_required(VERSION 3.14)

project(emotion_native_contract LANGUAGES C CXX)

option(EMOTION_SDK_BUILD_TESTS "Build native SDK contract tests" ON)

include(FetchContent)
FetchContent_Declare(
  nlohmann_json
  URL https://github.com/nlohmann/json/releases/download/v3.12.0/json.tar.xz
  SOURCE_SUBDIR json
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(nlohmann_json)

set(ENABLE_TESTING OFF CACHE BOOL "Disable mbedTLS tests" FORCE)
set(ENABLE_PROGRAMS OFF CACHE BOOL "Disable mbedTLS programs" FORCE)
FetchContent_Declare(
  mbedtls
  URL https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.5/mbedtls-3.6.5.tar.bz2
  SOURCE_SUBDIR mbedtls-3.6.5
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(mbedtls)

add_library(emotion_sdk_headers INTERFACE)
target_include_directories(emotion_sdk_headers INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

add_library(emotion_native_core STATIC
  src/crypto_aes_gcm.cpp
  src/crypto_sha256.cpp
  src/key_material.cpp
  src/license_state.cpp
  src/logging.cpp
  src/model_manifest.cpp
  src/model_package.cpp
  src/secure_store.cpp)
target_include_directories(emotion_native_core PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(emotion_native_core PRIVATE
  "${mbedtls_SOURCE_DIR}/mbedtls-3.6.5/include")
target_link_libraries(emotion_native_core PRIVATE
  mbedcrypto
  nlohmann_json::nlohmann_json)
set_target_properties(emotion_native_core PROPERTIES
  CXX_STANDARD 11
  CXX_STANDARD_REQUIRED YES
  CXX_EXTENSIONS NO)

if(EMOTION_SDK_BUILD_TESTS)
  enable_testing()

  add_executable(emotion_sdk_header_c_test
    tests/header_c_compile.c)
  target_link_libraries(emotion_sdk_header_c_test PRIVATE emotion_sdk_headers)
  add_test(NAME emotion_sdk_header_c_test COMMAND emotion_sdk_header_c_test)

  add_executable(emotion_sdk_header_cpp_test
    tests/header_cpp_compile.cpp)
  target_link_libraries(emotion_sdk_header_cpp_test PRIVATE emotion_sdk_headers)
  set_target_properties(emotion_sdk_header_cpp_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_sdk_header_cpp_test COMMAND emotion_sdk_header_cpp_test)

  add_executable(emotion_model_manifest_test
    tests/model_manifest_test.cpp)
  target_link_libraries(emotion_model_manifest_test PRIVATE emotion_native_core)
  target_compile_definitions(emotion_model_manifest_test PRIVATE
    EMOTION_TEST_MANIFEST_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../test/resources/model_manifests")
  set_target_properties(emotion_model_manifest_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_model_manifest_test COMMAND emotion_model_manifest_test)

  add_executable(emotion_crypto_sha256_test
    tests/crypto_sha256_test.cpp)
  target_link_libraries(emotion_crypto_sha256_test PRIVATE emotion_native_core)
  set_target_properties(emotion_crypto_sha256_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_crypto_sha256_test COMMAND emotion_crypto_sha256_test)

  add_executable(emotion_crypto_hkdf_test
    tests/crypto_hkdf_test.cpp)
  target_link_libraries(emotion_crypto_hkdf_test PRIVATE emotion_native_core)
  set_target_properties(emotion_crypto_hkdf_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_crypto_hkdf_test COMMAND emotion_crypto_hkdf_test)

  add_executable(emotion_crypto_aes_gcm_test
    tests/crypto_aes_gcm_test.cpp)
  target_link_libraries(emotion_crypto_aes_gcm_test PRIVATE emotion_native_core)
  set_target_properties(emotion_crypto_aes_gcm_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_crypto_aes_gcm_test COMMAND emotion_crypto_aes_gcm_test)

  add_executable(emotion_key_material_test
    tests/key_material_test.cpp)
  target_link_libraries(emotion_key_material_test PRIVATE emotion_native_core)
  set_target_properties(emotion_key_material_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_key_material_test COMMAND emotion_key_material_test)

  add_executable(emotion_license_state_test
    tests/license_state_test.cpp)
  target_link_libraries(emotion_license_state_test PRIVATE emotion_native_core)
  set_target_properties(emotion_license_state_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_license_state_test COMMAND emotion_license_state_test)

  add_executable(emotion_secure_store_test
    tests/secure_store_test.cpp)
  target_link_libraries(emotion_secure_store_test PRIVATE emotion_native_core)
  set_target_properties(emotion_secure_store_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_secure_store_test COMMAND emotion_secure_store_test)

  add_executable(emotion_logging_test
    tests/logging_test.cpp)
  target_link_libraries(emotion_logging_test PRIVATE emotion_native_core)
  set_target_properties(emotion_logging_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_logging_test COMMAND emotion_logging_test)

  add_executable(emotion_model_package_test
    tests/model_package_test.cpp)
  target_link_libraries(emotion_model_package_test PRIVATE emotion_native_core)
  target_compile_definitions(emotion_model_package_test PRIVATE
    EMOTION_TEST_PACKAGE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/resources")
  set_target_properties(emotion_model_package_test PROPERTIES
    CXX_STANDARD 11
    CXX_STANDARD_REQUIRED YES
    CXX_EXTENSIONS NO)
  add_test(NAME emotion_model_package_test COMMAND emotion_model_package_test)
endif()
