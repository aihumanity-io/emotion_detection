#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
native_dir=$(cd -- "$script_dir/.." && pwd)

if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 &&
  [ ! -x "${AARCH64_LINUX_GNU_ROOT:-}/bin/aarch64-linux-gnu-gcc" ]; then
  cat >&2 <<'EOF'
Missing Raspberry Pi ARM64 cross compiler.

Install a GCC aarch64-linux-gnu toolchain, or set:
  AARCH64_LINUX_GNU_ROOT=/path/to/toolchain

Optional sysroot:
  AARCH64_LINUX_GNU_SYSROOT=/path/to/rpi/sysroot
EOF
  exit 1
fi

cd "$native_dir"
cmake --preset rpi-aarch64-release
cmake --build --preset rpi-aarch64-release
