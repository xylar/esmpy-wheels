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

# fetch <url> <outfile>
fetch() {
  local url="$1" out="$2"
  if [ ! -f "$out" ]; then
    echo "==> Downloading $url"
    curl -fSL "$url" -o "$out"
  fi
}

build_hdf5() {
  local v="$HDF5_VERSION"
  local major="${v%.*}"          # e.g. 1.14.4.3 -> 1.14.4 ; adjust series below
  local series="${v%.*.*}"       # e.g. 1.14
  local tarball="$WORK_DIR/hdf5-$v.tar.gz"
  # HDF5 release URL layout: .../hdf5-<series>/hdf5-<major>/src/hdf5-<v>.tar.gz
  fetch "https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-$series/hdf5-$major/src/hdf5-$v.tar.gz" "$tarball"
  tar -xzf "$tarball" -C "$WORK_DIR"
  pushd "$WORK_DIR/hdf5-$v" >/dev/null
  ./configure --prefix="$DEPS_PREFIX" --enable-shared --disable-static \
      --with-pic --enable-hl
  make -j"$(_ncpu)"
  make install
  popd >/dev/null
}

build_netcdf_c() {
  local v="$NETCDF_C_VERSION"
  local tarball="$WORK_DIR/netcdf-c-$v.tar.gz"
  fetch "https://github.com/Unidata/netcdf-c/archive/refs/tags/v$v.tar.gz" "$tarball"
  tar -xzf "$tarball" -C "$WORK_DIR"
  pushd "$WORK_DIR/netcdf-c-$v" >/dev/null
  CPPFLAGS="-I$DEPS_PREFIX/include" LDFLAGS="-L$DEPS_PREFIX/lib" \
    ./configure --prefix="$DEPS_PREFIX" --enable-shared --disable-static \
      --disable-dap --disable-byterange --with-pic
  make -j"$(_ncpu)"
  make install
  popd >/dev/null
}

build_netcdf_fortran() {
  local v="$NETCDF_FORTRAN_VERSION"
  local tarball="$WORK_DIR/netcdf-fortran-$v.tar.gz"
  fetch "https://github.com/Unidata/netcdf-fortran/archive/refs/tags/v$v.tar.gz" "$tarball"
  tar -xzf "$tarball" -C "$WORK_DIR"
  pushd "$WORK_DIR/netcdf-fortran-$v" >/dev/null
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
