# esmpy-wheels

Build [PyPI](https://pypi.org/) wheels for **ESMPy**, the Python interface to the
[Earth System Modeling Framework (ESMF)](https://earthsystemmodeling.org/).

ESMPy is a thin, pure-Python `ctypes` layer that loads the compiled ESMF shared
library (`libesmf_fullylinked`) at import time. This repository builds ESMF and its
native dependencies, grafts them into a **relocatable, self-contained wheel**, and
publishes it so users can `pip install esmpy` without compiling ESMF themselves.

> **Status: work in progress.** The core feasibility check — does a wheel repair
> tool vendor a `dlopen`-only library? — is confirmed: serial + NetCDF wheels build
> in CI for Linux (`manylinux_2_28`), macOS arm64, and Windows (`win_amd64`, via
> MinGW/MSYS2) and import with `ESMFMKFILE` unset. The Windows wheel is validated
> under a stock python.org CPython, proving its vendored native-DLL closure is
> self-contained. The MPICH variant (`esmpy-mpich`) additionally builds for Linux +
> macOS and passes a `mpiexec -n 4` multi-rank check (see [MPI variant](#mpi-variant-esmpy-mpich)).
>
> Tracking:
> - Upstream ESMF issue: <https://github.com/esmf-org/esmf/issues/256>
>   ("Consider distributing ESMPy via PyPI", milestone v9.0.0) — the canonical
>   home for this effort; the wheel-aware loader change is intended to land there.
> - conda-forge discussion: <https://github.com/conda-forge/esmpy-feedstock/issues/72>

## Scope

| Axis | Supported now | Planned (additive) |
|------|---------------|--------------------|
| OS / arch | Linux x86_64 (manylinux_2_28), macOS arm64, Windows x86_64 (win_amd64) | + Linux aarch64, + Intel macOS |
| MPI  | serial (`mpiuni`) → `esmpy`; **MPICH → `esmpy-mpich`** (Linux + macOS) | + Open MPI (`esmpy-openmpi`) |
| I/O  | NetCDF-C + NetCDF-Fortran + HDF5 bundled | |

Two distribution names are published: **`esmpy`** (serial) and **`esmpy-mpich`**
(real ESMF MPI via MPICH). They share the `esmpy` import package but can't share a
runtime, so they are separate distributions (mirroring conda-forge's nompi/mpi split
and `mpi4py-mpich`). Windows is serial-only for now — there is no MPICH Windows wheel.

Intel macOS (osx-64) is intentionally deferred (see the CI matrix note): GitHub's
Intel runners are being deprecated and gfortran can't cross-compile x86_64 from
arm64. It can be re-added if demand justifies a paid/self-hosted Intel runner.

The whole pipeline is parameterized over `(os, arch, comm)`, so each added
platform / architecture / MPI flavor is a new CI matrix entry, not a redesign.

## How it works

Per `(os, arch)`, in CI:

1. **Build native deps from source, PIC** — HDF5 + NetCDF-C + NetCDF-Fortran into a
   staging prefix (`deps/build_deps_<os>.sh`). Conda binaries are *not* reused; they
   target conda's sysroot/glibc and are not `manylinux`-compliant.
2. **Build ESMF** into a staging prefix (`build/build_esmf.sh`, adapted from the
   conda-forge `esmf-feedstock` recipe): `ESMF_COMM=mpiuni`, `ESMF_NETCDF=split`,
   `ESMF_SHARED_LIB_BUILD=ON`. Produces `libesmf_fullylinked.{so,dylib}` + `esmf.mk`.
3. **Build the plain ESMPy wheel** from `esmf/src/addon/esmpy` (pure `py3-none-any`).
4. **Stage + graft** (`scripts/stage_esmf.py`, `scripts/graft_wheel.py`) — inject
   `libesmf_fullylinked.*` + `esmf.mk` into `esmpy/_esmf/lib/` inside the wheel and
   retag it. Because ESMPy has no extension module, the correct tag is
   `py3-none-<platform>` — **one wheel per (OS, arch)**, not one per Python version.
5. **Repair** — `auditwheel` (Linux) / `delocate` (macOS) scan the grafted
   `libesmf_fullylinked.*` and vendor its transitive dependencies (NetCDF, HDF5,
   libgfortran, ...) into the wheel with relocatable RPATHs.

At runtime the (upstream) ESMPy loader finds the bundled `esmf.mk` next to the
installed package and resolves the library directory relative to it, so no
`ESMFMKFILE` env var is needed. See the loader change tracked against ESMF itself.

> **Feasibility gate (Phase 0):** step 5 assumes the repair tools follow a
> non-extension library that nothing links against at build time (ESMPy `dlopen`s it
> by path). This must be confirmed before investing further.

## MPI variant (`esmpy-mpich`)

The MPICH build follows the mpi4py/PETSc model — **build against a source MPI, depend
on the runtime wheel**:

- **Build time:** MPICH is built from source (`deps/common.sh:build_mpich`, pinned in
  `versions.env`), and ESMF is built with `ESMF_COMM=mpich`. `ESMF_PIO=OFF` is kept so
  the only MPI dependency that enters `libesmf_fullylinked` is the **C** `libmpi`.
- **Runtime:** `libmpi` is **not** vendored (`auditwheel`/`delocate` exclude it);
  instead `esmpy-mpich` depends on the PyPI [`mpich`](https://pypi.org/project/mpich/)
  runtime wheel, which supplies `libmpi.so.12` (macOS `libmpi.12.dylib`) **and**
  `mpiexec`. The ESMPy loader preloads that `libmpi` before `dlopen`-ing ESMF.

```bash
pip install esmpy-mpich                  # pulls the `mpich` runtime wheel too
mpiexec -n 4 python my_regrid_script.py  # real multi-rank ESMF VM
```

This keeps a single MPI runtime in the environment (so `pip install mpi4py` shares the
same ABI-compatible MPI) and targets **single-node** parallelism. Because MPICH honors
the [MPI ABI-compatibility initiative](https://www.mpich.org/abi/) (`libmpi.so.12`), the
`mpich` runtime can in principle be pointed at a system MPI (Intel MPI, Cray MPT) — a
best-effort escape hatch, but genuine multi-node HPC still wants a spack/system build.

## Layout

```
versions.env              pinned ESMF ref + HDF5/NetCDF-C/Fortran versions
esmf/                     ESMF source, fetched by scripts/fetch_esmf.sh (gitignored)
deps/
  common.sh               shared download/build helpers for the native deps
  build_deps_linux.sh     build PIC HDF5 + NetCDF-C/Fortran (Linux/manylinux)
  build_deps_macos.sh     same for macOS (x86_64 + arm64)
build/
  build_esmf.sh           build + install ESMF into a staging prefix
scripts/
  fetch_esmf.sh           shallow-clone the pinned ESMF ref into ./esmf
  stage_esmf.py           collect libesmf_fullylinked + esmf.mk from the install
  graft_wheel.py          inject them into the wheel and retag py3-none-<platform>
.github/workflows/
  wheels.yml              matrix build -> graft -> repair -> test (artifacts only)
```

The ESMPy Python source comes from the ESMF ref pinned in `versions.env`, so version
and code stay in lockstep with ESMF. That ref must contain the wheel-aware loader
change; until it is upstream in esmf-org, it points at a fork branch.

## Building locally

```bash
bash scripts/fetch_esmf.sh             # shallow-clone ESMF at the pinned ref
source versions.env
bash deps/build_deps_linux.sh          # or build_deps_macos.sh
bash build/build_esmf.sh               # (also fetches ESMF if needed)
python -m build --wheel esmf/src/addon/esmpy --outdir dist
python scripts/stage_esmf.py --install-prefix _esmf_install --dest dist/staged_lib
python scripts/graft_wheel.py --wheel dist/esmpy-*-py3-none-any.whl \
    --lib-dir dist/staged_lib --plat linux_x86_64 --outdir wheelhouse
auditwheel repair wheelhouse/esmpy-*.whl -w wheelhouse   # delocate-wheel on macOS
```

## Relationship to conda-forge

The conda-forge `esmf-feedstock` / `esmpy-feedstock` are the recipe/dependency
**blueprint** for this repo (build flags, dependency versions, `esmf.mk` path
handling). Their *binaries* are not reused — manylinux wheels rebuild the native
stack from source. This repo intentionally mirrors the feedstock split: ESMF (the
native library) and ESMPy (the Python layer) are built here as one self-contained
wheel rather than two conda packages.

## License

ESMF and ESMPy are licensed under the University of Illinois/NCSA Open Source
License (see [`LICENSE`](LICENSE)). Wheels built here redistribute ESMF — and the
bundled NetCDF, HDF5, and compiler runtime libraries — in binary form under their
respective licenses.
