#!/usr/bin/env python3
"""Collect the ESMF artifacts a wheel needs from an ESMF install prefix.

Finds ``esmf.mk`` under the install prefix, reads ``ESMF_LIBSDIR`` from it, and
copies ``esmf.mk`` plus ``libesmf_fullylinked.{so,dylib}`` into a staging directory
that ``graft_wheel.py`` then injects into the ESMPy wheel (as ``esmpy/_esmf/lib/``).

Only the shared library and esmf.mk are staged -- the ESMPy loader reads a handful
of variables from esmf.mk and ``dlopen``s the library; the other esmf.mk entries
(compiler paths, etc.) are unused at runtime.
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path


def find_esmf_mk(install_prefix: Path) -> Path:
    matches = sorted(install_prefix.rglob("esmf.mk"))
    if not matches:
        sys.exit(f"error: no esmf.mk found under {install_prefix}")
    if len(matches) > 1:
        print(f"warning: multiple esmf.mk found, using {matches[0]}", file=sys.stderr)
    return matches[0]


# Import/static/libtool artifacts that share the libesmf_fullylinked stem but are not
# the runtime object we want to graft. On Windows the shared build emits both
# libesmf_fullylinked.dll (runtime) and libesmf_fullylinked.dll.a (import lib); we
# stage only the former. On Linux/macOS there is nothing to filter.
_NON_RUNTIME_SUFFIXES = (".a", ".lib", ".la", ".exp", ".def")


def _runtime_only(paths) -> list[Path]:
    """Drop import/static/libtool artifacts, keeping only loadable objects."""
    return [p for p in sorted(paths) if p.suffix not in _NON_RUNTIME_SUFFIXES]


def find_runtime_libs(libsdir: str, install_prefix: Path) -> list[Path]:
    """Locate the runtime libesmf_fullylinked object(s).

    Searches, in order of preference: ``libsdir`` (ESMF_LIBSDIR from esmf.mk), then
    the whole install prefix recursively. On Windows the ``.dll`` does not install
    next to the ``.dll.a`` import lib in ``lib/libO/...`` -- it lands in a parallel
    ``bin/binO/MinGW.*`` tree -- so a flat sibling-``bin/`` glob misses it; recursing
    the prefix finds it wherever ESMF's install layout puts it. Import/static libs
    are filtered out so only the loadable object (.so/.dylib/.dll) is returned.
    """
    lib_dir = Path(libsdir)
    libs = _runtime_only(lib_dir.glob("libesmf_fullylinked.*"))
    if libs:
        return libs
    return _runtime_only(install_prefix.rglob("libesmf_fullylinked.*"))


def read_mk_var(esmf_mk: Path, key: str) -> str | None:
    for line in esmf_mk.read_text().splitlines():
        stripped = line.strip()
        # esmf.mk uses both `KEY=value` and `KEY: value` forms
        for sep in ("=", ":"):
            prefix = f"{key}{sep}"
            if stripped.startswith(prefix):
                return stripped[len(prefix):].strip()
    return None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install-prefix", required=True, type=Path,
                        help="ESMF install prefix (ESMF_INSTALL_PREFIX)")
    parser.add_argument("--dest", type=Path, default=Path("dist/staged_lib"),
                        help="staging output directory (default: dist/staged_lib)")
    args = parser.parse_args()

    install_prefix = args.install_prefix.resolve()
    esmf_mk = find_esmf_mk(install_prefix)
    libsdir = read_mk_var(esmf_mk, "ESMF_LIBSDIR")
    version = read_mk_var(esmf_mk, "ESMF_VERSION_STRING")
    if not libsdir:
        sys.exit(f"error: ESMF_LIBSDIR not found in {esmf_mk}")

    lib_dir = Path(libsdir)
    libs = find_runtime_libs(libsdir, install_prefix)
    if not libs:
        # Inventory every libesmf* artifact anywhere under the prefix so the CI log
        # is decisive: if the fullylinked runtime object is simply absent (the link
        # failed), this shows exactly what *was* produced instead.
        inventory = sorted(install_prefix.rglob("libesmf*"))
        listing = "\n".join(f"  {p.relative_to(install_prefix)}" for p in inventory) \
            or "  (no libesmf* files found at all)"
        sys.exit(f"error: no runtime libesmf_fullylinked.* found under {install_prefix}\n"
                 f"ESMF_LIBSDIR was {lib_dir}\n"
                 f"libesmf* artifacts present under the prefix:\n{listing}")

    args.dest.mkdir(parents=True, exist_ok=True)
    shutil.copy2(esmf_mk, args.dest / "esmf.mk")
    for lib in libs:
        # follow symlinks so the real object is staged under the expected name
        shutil.copy2(lib.resolve(), args.dest / lib.name)

    print(f"ESMF version : {version}")
    print(f"lib dir      : {lib_dir}")
    print(f"staged into  : {args.dest}")
    for path in sorted(args.dest.iterdir()):
        print(f"  {path.name}")


if __name__ == "__main__":
    main()
