#!/usr/bin/env bash
#
# Build the native dependency stack (HDF5 + NetCDF-C + NetCDF-Fortran) for Linux
# wheels. Intended to run inside a manylinux container so the resulting wheel is
# policy-compliant. See deps/common.sh for the actual build steps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO_ROOT/versions.env"

export DEPS_PREFIX="${DEPS_PREFIX:-$REPO_ROOT/_deps}"
export WORK_DIR="${WORK_DIR:-$REPO_ROOT/build/work}"

export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"   # only the MPICH build (MPI variant) uses this
export FC="${FC:-gfortran}"
# -fPIC is required for the fully-linked ESMF library. Static libgcc/libstdc++
# reduces the risk of runtime version conflicts on old glibc (see netcdf4-win-wheels).
export CFLAGS="${CFLAGS:-} -fPIC"
export FFLAGS="${FFLAGS:-} -fPIC -fallow-argument-mismatch"
export LDFLAGS="${LDFLAGS:-} -Wl,-rpath,$DEPS_PREFIX/lib"

# shellcheck source=deps/common.sh
source "$SCRIPT_DIR/common.sh"
build_all_deps
