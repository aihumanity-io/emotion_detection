set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(_emotion_rpi_toolchain_prefix "$ENV{AARCH64_LINUX_GNU_ROOT}")
if(_emotion_rpi_toolchain_prefix)
  set(_emotion_rpi_toolchain_bin "${_emotion_rpi_toolchain_prefix}/bin/")
else()
  set(_emotion_rpi_toolchain_bin "")
endif()

set(CMAKE_C_COMPILER "${_emotion_rpi_toolchain_bin}aarch64-linux-gnu-gcc" CACHE FILEPATH
  "Raspberry Pi ARM64 C compiler")
set(CMAKE_CXX_COMPILER "${_emotion_rpi_toolchain_bin}aarch64-linux-gnu-g++" CACHE FILEPATH
  "Raspberry Pi ARM64 C++ compiler")

set(_emotion_rpi_sysroot "$ENV{AARCH64_LINUX_GNU_SYSROOT}")
if(_emotion_rpi_sysroot)
  set(CMAKE_SYSROOT "${_emotion_rpi_sysroot}" CACHE PATH
    "Raspberry Pi ARM64 sysroot")
  set(CMAKE_FIND_ROOT_PATH "${_emotion_rpi_sysroot}")
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
endif()

set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
