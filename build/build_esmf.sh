#!/usr/bin/env bash
#
# Build ESMF (from the pinned esmf/ submodule) into a staging prefix and install it,
# producing libesmf_fullylinked.{so,dylib} + esmf.mk for the wheel graft step.
#
# Adapted from the conda-forge esmf-feedstock recipe (recipe/build.sh). First
# milestone: serial (ESMF_COMM=mpiuni) + NetCDF (split), shared/fully-linked build.
#
# Inputs (env, with defaults):
#   REPO_ROOT           repo checkout root                 (default: script's ../)
#   DEPS_PREFIX         where HDF5/NetCDF were installed    (default: $REPO_ROOT/_deps)
#   ESMF_INSTALL_PREFIX where ESMF is installed             (default: $REPO_ROOT/_esmf_install)
#   ESMF_COMM           MPI flavor                          (default: mpiuni, from versions.env)
#   ESMF_BOPT           O (optimized) or g (debug)          (default: O)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=/dev/null
source "$REPO_ROOT/versions.env"

DEPS_PREFIX="${DEPS_PREFIX:-$REPO_ROOT/_deps}"
export ESMF_INSTALL_PREFIX="${ESMF_INSTALL_PREFIX:-$REPO_ROOT/_esmf_install}"

# Fetch the ESMF source (at the pinned ref) if it is not already present.
bash "$REPO_ROOT/scripts/fetch_esmf.sh"

# --- ESMF build configuration -------------------------------------------------
export ESMF_DIR="$REPO_ROOT/esmf"
export ESMF_COMM="${ESMF_COMM:-mpiuni}"
export ESMF_BOPT="${ESMF_BOPT:-O}"
export ESMF_SHARED_LIB_BUILD=ON

# Compiler + OS: gfortran + gcc/g++ on Linux; clang C++ + gfortran on macOS;
# MinGW-w64 gfortran on Windows (ESMF only supports Windows via MinGW/Cygwin, not
# native MSVC). Under MSYS2 the MINGW64 shell reports uname -s as MINGW64_NT-*.
case "$(uname -s)" in
  Darwin)
    export ESMF_COMPILER="${ESMF_COMPILER:-gfortranclang}"
    ;;
  MINGW*|MSYS*)
    export ESMF_OS="${ESMF_OS:-MinGW}"
    export ESMF_COMPILER="${ESMF_COMPILER:-gfortran}"
    export ESMF_ABI="${ESMF_ABI:-64}"
    # ESMF_MACHINE auto-detects to `uname -m` (x86_64); the pinned ESMF ref accepts
    # that in its MinGW build_rules.mk (older ESMF only recognized the i686 label).
    ;;
  *)
    export ESMF_COMPILER="${ESMF_COMPILER:-gfortran}"
    ;;
esac

# gfortran >= 10 rejects legacy argument-mismatch by default; ESMF/deps need this.
export ESMF_F90COMPILEOPTS="${ESMF_F90COMPILEOPTS:-} -fallow-argument-mismatch"

# NetCDF (split: separate netcdf-c and netcdf-fortran) from the deps prefix.
export ESMF_NETCDF=split
export ESMF_NETCDF_INCLUDE="$DEPS_PREFIX/include"
export ESMF_NETCDF_LIBPATH="$DEPS_PREFIX/lib"
export ESMF_NETCDF_LIBS="-lnetcdff -lnetcdf"

# PIO requires MPI; disable it for the serial (mpiuni) milestone.
if [ "$ESMF_COMM" = "mpiuni" ]; then
  export ESMF_PIO=OFF
else
  export ESMF_PIO=internal
fi

# Internal LAPACK/MOAB/YAMLCPP (defaults) -> no extra external deps to bundle.

# Ensure the freshly built deps are found at link/run time. On Windows there is no
# LD_LIBRARY_PATH/rpath: DLLs are resolved via PATH, so prepend the deps bin dir.
export LD_LIBRARY_PATH="$DEPS_PREFIX/lib:${LD_LIBRARY_PATH:-}"
export DYLD_LIBRARY_PATH="$DEPS_PREFIX/lib:${DYLD_LIBRARY_PATH:-}"
case "$(uname -s)" in
  MINGW*|MSYS*) export PATH="$DEPS_PREFIX/bin:$DEPS_PREFIX/lib:$PATH" ;;
esac

# --- Build --------------------------------------------------------------------
NPROC="$( (command -v nproc >/dev/null && nproc) || sysctl -n hw.ncpu || echo 2)"

echo "==> ESMF build configuration:"
make -C "$ESMF_DIR" info

echo "==> Building ESMF (-j$NPROC) ..."
make -C "$ESMF_DIR" -j"$NPROC"

echo "==> Installing ESMF to $ESMF_INSTALL_PREFIX ..."
make -C "$ESMF_DIR" install

# The installed esmf.mk bakes absolute build paths; the runtime loader resolves the
# library dir relative to esmf.mk, but normalize any staging-prefix leakage anyway
# (mirrors the feedstock's sed fixup).
ESMF_MK="$(find "$ESMF_INSTALL_PREFIX" -name esmf.mk -print -quit)"
echo "==> Installed esmf.mk: $ESMF_MK"

# Inventory the installed libesmf* artifacts (name + location). This makes the log
# self-diagnosing: whether libesmf_fullylinked.dll got built (and into lib/ vs the
# bin/binO tree) or the fullylinked link failed silently is visible right here,
# without needing a separate stage_esmf.py run.
echo "==> Installed libesmf* artifacts:"
find "$ESMF_INSTALL_PREFIX" -iname 'libesmf*' -printf '    %p\n' 2>/dev/null \
  || find "$ESMF_INSTALL_PREFIX" -iname 'libesmf*' -exec echo '    {}' \;

echo "==> Done. Next: python scripts/stage_esmf.py --install-prefix $ESMF_INSTALL_PREFIX ..."
