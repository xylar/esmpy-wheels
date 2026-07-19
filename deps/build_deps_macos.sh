#!/usr/bin/env bash
#
# Build the native dependency stack (HDF5 + NetCDF-C + NetCDF-Fortran) for macOS
# wheels (x86_64 or arm64). See deps/common.sh for the actual build steps.
#
# ARCH selects the target architecture: x86_64 | arm64 (default: host arch).
# MACOSX_DEPLOYMENT_TARGET should match the runner / desired minimum macOS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO_ROOT/versions.env"

export DEPS_PREFIX="${DEPS_PREFIX:-$REPO_ROOT/_deps}"
export WORK_DIR="${WORK_DIR:-$REPO_ROOT/build/work}"

ARCH="${ARCH:-$(uname -m)}"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"

# clang for C; a real gfortran (e.g. from Homebrew) is required for the Fortran deps.
export CC="${CC:-clang}"
export CXX="${CXX:-clang++}"   # only the MPICH build (MPI variant) uses this
export FC="${FC:-gfortran}"
export CFLAGS="${CFLAGS:-} -fPIC -arch $ARCH"
export FFLAGS="${FFLAGS:-} -fPIC -fallow-argument-mismatch"
export LDFLAGS="${LDFLAGS:-} -Wl,-rpath,$DEPS_PREFIX/lib"

# shellcheck source=deps/common.sh
source "$SCRIPT_DIR/common.sh"
build_all_deps
