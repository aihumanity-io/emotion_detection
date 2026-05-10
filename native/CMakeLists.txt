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

add_library(emotion_sdk_headers INTERFACE)
target_include_directories(emotion_sdk_headers INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

add_library(emotion_native_core STATIC
  src/crypto_sha256.cpp
  src/model_manifest.cpp)
target_include_directories(emotion_native_core PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(emotion_native_core PRIVATE
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
endif()
