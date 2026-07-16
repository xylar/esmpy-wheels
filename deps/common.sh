#!/usr/bin/env bash
#
# Shared helpers to build the native stack (HDF5 + NetCDF-C + NetCDF-Fortran) from
# source, position-independent, into $DEPS_PREFIX. Sourced by build_deps_<os>.sh.
#
# The fully-linked ESMF library requires all third-party deps to be available as
# PIC; building shared libraries here lets auditwheel/delocate vendor them via the
# NetCDF NEEDED chain (NetCDF -> HDF5).
#
# Expects the following to be set by the caller before sourcing/using:
#   DEPS_PREFIX   install prefix                (e.g. $REPO_ROOT/_deps)
#   WORK_DIR      scratch build dir             (e.g. $REPO_ROOT/build/work)
#   CC, FC        C and Fortran compilers
#   CFLAGS/FFLAGS extra flags (must include -fPIC)
# and the *_VERSION vars from versions.env.

set -euo pipefail

_ncpu() { (command -v nproc >/dev/null && nproc) || sysctl -n hw.ncpu || echo 2; }

# download_extract <url> <cache_tarball> -> echoes the extracted source dir.
# Extracts into a fresh temp dir and returns its single top-level subdirectory, so
# it is robust to irregular archive naming and to tarballs that list a "./" member
# (e.g. HDF5, whose source unpacks to hdf5-1.14.4-3/).
download_extract() {
  local url="$1" tarball="$2"
  if [ ! -f "$tarball" ]; then
    echo "==> Downloading $url" >&2
    curl -fSL "$url" -o "$tarball"
  fi
  local d; d="$(mktemp -d "${WORK_DIR:?}/extract.XXXXXX")"
  tar -xzf "$tarball" -C "$d"
  local sub; sub="$(find "$d" -mindepth 1 -maxdepth 1 -type d | head -1)"
  if [ -z "$sub" ]; then
    echo "error: no source directory extracted from $tarball" >&2
    return 1
  fi
  echo "$sub"
}

build_hdf5() {
  local src; src="$(download_extract "$HDF5_URL" "$WORK_DIR/hdf5-$HDF5_VERSION.tar.gz")"
  pushd "$src" >/dev/null
  ./configure --prefix="$DEPS_PREFIX" --enable-shared --disable-static --enable-hl
  make -j"$(_ncpu)"
  make install
  popd >/dev/null
}

build_netcdf_c() {
  local src; src="$(download_extract "$NETCDF_C_URL" "$WORK_DIR/netcdf-c-$NETCDF_C_VERSION.tar.gz")"
  pushd "$src" >/dev/null
  CPPFLAGS="-I$DEPS_PREFIX/include" LDFLAGS="-L$DEPS_PREFIX/lib" \
    ./configure --prefix="$DEPS_PREFIX" --enable-shared --disable-static \
      --disable-dap --disable-byterange --with-pic
  make -j"$(_ncpu)"
  make install
  popd >/dev/null
}

build_netcdf_fortran() {
  local src; src="$(download_extract "$NETCDF_FORTRAN_URL" "$WORK_DIR/netcdf-fortran-$NETCDF_FORTRAN_VERSION.tar.gz")"
  pushd "$src" >/dev/null
  CPPFLAGS="-I$DEPS_PREFIX/include" LDFLAGS="-L$DEPS_PREFIX/lib" \
    LD_LIBRARY_PATH="$DEPS_PREFIX/lib:${LD_LIBRARY_PATH:-}" \
    ./configure --prefix="$DEPS_PREFIX" --enable-shared --disable-static --with-pic
  make -j"$(_ncpu)"
  make install
  popd >/dev/null
}

build_all_deps() {
  mkdir -p "$DEPS_PREFIX" "$WORK_DIR"
  build_hdf5
  build_netcdf_c
  build_netcdf_fortran
  echo "==> Native deps installed into $DEPS_PREFIX"
}
