#!/usr/bin/env python3
"""Retarget the ESMPy pyproject to an MPI-specific distribution, in place.

The MPI-enabled wheel is published under a distinct distribution name (e.g.
``esmpy-mpich``) that depends on a PyPI MPI *runtime* wheel (e.g. ``mpich``,
which ships libmpi + mpiexec). ESMPy's own ``pyproject.toml`` hard-codes
``name = "esmpy"`` and does not list an MPI dependency, so the CI overlays this
at build time -- a build-only edit to the fetched ESMF checkout, never committed
upstream -- so the same source tree yields the serial ``esmpy`` wheel or an MPI
wheel purely by variant. The *import* package remains ``esmpy``; only the
distribution name and its dependencies change.

Text edits (not a TOML round-trip) to preserve the file's formatting/comments.
"""
from __future__ import annotations

import argparse
import pathlib
import sys


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pyproject", required=True, type=pathlib.Path,
                        help="path to esmpy's pyproject.toml")
    parser.add_argument("--dist-name", required=True,
                        help="new [project] name, e.g. esmpy-mpich")
    parser.add_argument("--require", action="append", default=[],
                        help="a runtime dependency to add, e.g. 'mpich >= 5.0.1' "
                             "(repeatable)")
    args = parser.parse_args()

    text = args.pyproject.read_text()

    if 'name = "esmpy"' not in text:
        sys.exit('error: could not find `name = "esmpy"` in '
                 f"{args.pyproject}")
    if "dependencies = [\n" not in text:
        sys.exit(f"error: could not find `dependencies = [` in {args.pyproject}")

    text = text.replace('name = "esmpy"', f'name = "{args.dist_name}"', 1)

    if args.require:
        added = "".join(f'    "{req}",\n' for req in args.require)
        text = text.replace("dependencies = [\n",
                            "dependencies = [\n" + added, 1)

    args.pyproject.write_text(text)
    print(f"set distribution name -> {args.dist_name}"
          + (f"; added deps {args.require}" if args.require else ""))


if __name__ == "__main__":
    main()
