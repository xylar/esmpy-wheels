#!/usr/bin/env python3
"""Graft the staged ESMF library + esmf.mk into a pure ESMPy wheel and retag it.

ESMPy has no compiled extension module, so ``python -m build`` produces a pure
``esmpy-<ver>-py3-none-any.whl``. This script:

  1. unpacks that wheel,
  2. copies the staged files (libesmf_fullylinked.*, esmf.mk) into
     ``esmpy/_esmf/lib/`` inside it,
  3. flips ``Root-Is-Purelib`` to false and rewrites the wheel tag to
     ``py3-none-<platform>`` (one wheel per OS/arch, valid for all Python 3.x
     because there is no extension), and
  4. recomputes RECORD and repacks.

The output is a platform wheel ready for ``auditwheel repair`` (Linux) or
``delocate-wheel`` (macOS), which vendor the transitive native dependencies of the
grafted library.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path


def _record_hash(data: bytes) -> str:
    digest = hashlib.sha256(data).digest()
    b64 = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return f"sha256={b64}"


def parse_wheel_name(wheel: Path) -> dict[str, str]:
    stem = wheel.name[: -len(".whl")]
    parts = stem.split("-")
    # {dist}-{version}(-{build})?-{python}-{abi}-{platform}
    if len(parts) == 5:
        dist, version, python, abi, platform = parts
        build = ""
    elif len(parts) == 6:
        dist, version, build, python, abi, platform = parts
    else:
        sys.exit(f"error: cannot parse wheel filename: {wheel.name}")
    return {"dist": dist, "version": version, "build": build,
            "python": python, "abi": abi, "platform": platform}


def retag_wheel_file(wheel_dir: Path, python: str, abi: str, platform: str) -> None:
    dist_info = next(wheel_dir.glob("*.dist-info"), None)
    if dist_info is None:
        sys.exit("error: no .dist-info directory in wheel")
    wheel_meta = dist_info / "WHEEL"
    lines = []
    saw_tag = False
    for line in wheel_meta.read_text().splitlines():
        if line.startswith("Root-Is-Purelib:"):
            lines.append("Root-Is-Purelib: false")
        elif line.startswith("Tag:"):
            if not saw_tag:  # collapse to a single new tag
                lines.append(f"Tag: {python}-{abi}-{platform}")
                saw_tag = True
        else:
            lines.append(line)
    if not saw_tag:
        lines.append(f"Tag: {python}-{abi}-{platform}")
    wheel_meta.write_text("\n".join(lines) + "\n")


def rewrite_record(wheel_dir: Path) -> None:
    dist_info = next(wheel_dir.glob("*.dist-info"))
    record_path = dist_info / "RECORD"
    entries: list[str] = []
    for path in sorted(wheel_dir.rglob("*")):
        if path.is_dir():
            continue
        rel = path.relative_to(wheel_dir).as_posix()
        if rel == f"{dist_info.name}/RECORD":
            continue
        data = path.read_bytes()
        entries.append(f"{rel},{_record_hash(data)},{len(data)}")
    entries.append(f"{dist_info.name}/RECORD,,")
    record_path.write_text("\n".join(entries) + "\n")


def repack(wheel_dir: Path, out_wheel: Path) -> None:
    out_wheel.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out_wheel, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(wheel_dir.rglob("*")):
            if path.is_file():
                zf.write(path, path.relative_to(wheel_dir).as_posix())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wheel", required=True, type=Path,
                        help="input pure esmpy-*-py3-none-any.whl")
    parser.add_argument("--lib-dir", required=True, type=Path,
                        help="staged dir from stage_esmf.py (libesmf_fullylinked.*, esmf.mk)")
    parser.add_argument("--plat", required=True,
                        help="platform tag, e.g. linux_x86_64 or macosx_11_0_arm64")
    parser.add_argument("--pkg-subdir", default="esmpy/_esmf/lib",
                        help="destination inside the package (default: esmpy/_esmf/lib)")
    parser.add_argument("--outdir", type=Path, default=Path("wheelhouse"))
    args = parser.parse_args()

    tags = parse_wheel_name(args.wheel)

    with tempfile.TemporaryDirectory() as tmp:
        wheel_dir = Path(tmp)
        with zipfile.ZipFile(args.wheel) as zf:
            zf.extractall(wheel_dir)

        dest = wheel_dir / args.pkg_subdir
        dest.mkdir(parents=True, exist_ok=True)
        staged = [p for p in args.lib_dir.iterdir() if p.is_file()]
        if not staged:
            sys.exit(f"error: no files staged in {args.lib_dir}")
        for path in staged:
            shutil.copy2(path, dest / path.name)

        retag_wheel_file(wheel_dir, tags["python"], tags["abi"], args.plat)
        rewrite_record(wheel_dir)

        out_name = (f"{tags['dist']}-{tags['version']}-"
                    f"{tags['python']}-{tags['abi']}-{args.plat}.whl")
        out_wheel = args.outdir / out_name
        repack(wheel_dir, out_wheel)

    print(f"grafted wheel: {out_wheel}")


if __name__ == "__main__":
    main()
