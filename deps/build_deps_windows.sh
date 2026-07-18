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
#
# Demote GCC 14's newly-default errors back to warnings. MSYS2 ships GCC 14+, which
# promoted several long-standing C warnings to hard errors; the 2022-era netcdf-c
# 4.9.0 sources trip them (e.g. dpathmgr.c's Windows _wstat64 path passes
# `struct stat *` where `struct _stat64 *` is expected -> -Werror=incompatible-
# pointer-types). Older GCC accepted these with a warning. Relaxing the error-ness
# restores the pre-GCC-14 behavior without changing codegen.
GCC14_RELAX="-Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration"
GCC14_RELAX="$GCC14_RELAX -Wno-error=int-conversion -Wno-error=implicit-int"
export CFLAGS="${CFLAGS:-} $GCC14_RELAX"
export FFLAGS="${FFLAGS:-} -fallow-argument-mismatch"

# Export the whole symbol table from the netcdf DLLs. netcdf-c bundles code that
# carries __declspec(dllexport) (nczarr/ncpoco/...), and on MinGW *any* explicit
# dllexport disables ld's auto-export-all -> the plain-extern netcdf C API never
# lands in the DLL's export table, so its import lib (.dll.a) is missing nc_create,
# nc_def_dim, etc. and anything linking -lnetcdf (netcdf's own ncgen/ncdump tools,
# and later ESMF) fails with undefined references. --export-all-symbols overrides
# that and exports everything. (Same fix as ESMF's --export-all-symbols.) common.sh
# threads this LDFLAGS into the netcdf-c/netcdf-fortran configure links.
export LDFLAGS="${LDFLAGS:-} -Wl,--export-all-symbols"

# Disable HDF5's _Float16 conversions on MinGW: gcc advertises the _Float16 type but
# MinGW's <float.h> does not define FLT16_MAX, so those H5Tconv.c functions fail to
# compile. Nothing in the ESMF/NetCDF stack uses HDF5 float16 (MSYS2's own HDF5
# package disables it too).
export HDF5_CONFIGURE_EXTRA="--enable-nonstandard-feature-float16=no"

# shellcheck source=deps/common.sh
source "$SCRIPT_DIR/common.sh"
build_all_deps
