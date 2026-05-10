cmake_minimum_required(VERSION 3.14)

project(emotion_native_contract LANGUAGES C CXX)

option(EMOTION_SDK_BUILD_TESTS "Build native SDK contract tests" ON)

add_library(emotion_sdk_headers INTERFACE)
target_include_directories(emotion_sdk_headers INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

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
endif()
