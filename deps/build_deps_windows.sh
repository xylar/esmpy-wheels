#!/usr/bin/env bash
#
# Build the native dependency stack (HDF5 + NetCDF-C + NetCDF-Fortran) for Windows
# wheels, using the MinGW-w64 toolchain from MSYS2. See deps/common.sh for the
# actual build steps.
#
# Runs inside the MSYS2 MINGW64 shell. zlib is provided by MSYS2
# (mingw-w64-x86_64-zlib in /mingw64) rather than built from source -- this mirrors
# how Linux/macOS treat zlib (system-provided) and sits at the same toolchain
# boundary as the MinGW compiler-runtime DLLs (libgfortran/libstdc++/...), which
# are likewise provided by /mingw64. HDF5's configure finds it automatically because
# /mingw64/{include,lib} is on the MinGW gcc default search path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO_ROOT/versions.env"

export DEPS_PREFIX="${DEPS_PREFIX:-$REPO_ROOT/_deps}"
export WORK_DIR="${WORK_DIR:-$REPO_ROOT/build/work}"

export CC="${CC:-gcc}"
export FC="${FC:-gfortran}"
# No -fPIC: it is a no-op on Windows (all code is position-independent) and only
# emits a warning. No -Wl,-rpath either: Windows resolves DLLs via PATH, not rpath
# (build_esmf.sh prepends $DEPS_PREFIX/bin + /lib to PATH for the ESMF link/run).
export CFLAGS="${CFLAGS:-}"
export FFLAGS="${FFLAGS:-} -fallow-argument-mismatch"

# Disable HDF5's _Float16 conversions on MinGW: gcc advertises the _Float16 type but
# MinGW's <float.h> does not define FLT16_MAX, so those H5Tconv.c functions fail to
# compile. Nothing in the ESMF/NetCDF stack uses HDF5 float16 (MSYS2's own HDF5
# package disables it too).
export HDF5_CONFIGURE_EXTRA="--enable-nonstandard-feature-float16=no"

# shellcheck source=deps/common.sh
source "$SCRIPT_DIR/common.sh"
build_all_deps
