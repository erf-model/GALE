#!/usr/bin/env bash
# Download, build and install the ROSCO turbine controller library (libdiscon) that OpenFAST's
# ServoDyn loads at run time.
#
#   Build/setup_rosco.sh [--version 2.10.1] [--prefix DIR] [--src DIR] [--jobs N]
#                        [--fortran gfortran] [--force]
#
# Clones the release tag of https://github.com/NREL/ROSCO into <src>/rosco-<version>, builds the
# controller (rosco/controller) as a shared library and installs it as <prefix>/lib/libdiscon.so
# (.dylib on macOS; default prefix $HOME/opt/rosco-<version>). It then prints the -DROSCO_DIR to
# pass to GALE's cmake and the --libdiscon to pass to
# Exec/CanonicalTests/MovingBodies/OpenFAST_IEA15_PowerCurve/prepare.py. Re-running is safe: an
# existing clone is reused and an existing install is left alone unless --force is given.
# GALE does not link against ROSCO; only the turbine models that name it in their ServoDyn file
# need it. 2.10.1 is the tested version. Build it with the Fortran compiler OpenFAST was built with.
set -euo pipefail

version="2.10.1"
src_root="${HOME}/opt/src"
prefix=""
jobs=4
fortran="${FC:-gfortran}"
force=0
repo="https://github.com/NREL/ROSCO"

usage() { sed -n '2,15p' "$0"; exit "${1:-0}"; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)   version="$2"; shift 2 ;;
        --prefix)    prefix="$2"; shift 2 ;;
        --src)       src_root="$2"; shift 2 ;;
        --jobs|-j)   jobs="$2"; shift 2 ;;
        --fortran)   fortran="$2"; shift 2 ;;
        --force)     force=1; shift ;;
        -h|--help)   usage 0 ;;
        *) echo "setup_rosco.sh: unknown argument '$1'" >&2; usage 1 ;;
    esac
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "setup_rosco.sh: --version must look like 2.10.1, not '$version'" >&2; exit 1; }
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "setup_rosco.sh: --jobs must be a positive whole number, not '$jobs'" >&2; exit 1; }
[[ -n "$prefix" ]] || prefix="${HOME}/opt/rosco-${version}"
for tool in git cmake "$fortran"; do
    command -v "$tool" > /dev/null || { echo "setup_rosco.sh: '$tool' not found in PATH" >&2; exit 1; }
done

installed_library() {
    local f
    for f in "$prefix/lib/libdiscon.so" "$prefix/lib/libdiscon.dylib"; do
        if [[ -f "$f" ]]; then echo "$f"; return 0; fi
    done
    return 0
}
report() {
    echo "  GALE: cmake ... -DERF_ENABLE_OPENFAST=ON -DOPENFAST_DIR=<OpenFAST prefix> -DROSCO_DIR=$prefix"
    echo "  power-curve case: python3 prepare.py --libdiscon $1"
}

src="${src_root}/rosco-${version}"
if [[ -d "$src/.git" ]]; then
    echo "setup_rosco.sh: reusing the source in $src"
else
    mkdir -p "$src_root"
    echo "setup_rosco.sh: cloning ROSCO v${version} into $src"
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v${version}" "$repo" "$src"
fi
[[ -f "$src/rosco/controller/CMakeLists.txt" ]] || { echo "setup_rosco.sh: $src has no rosco/controller/CMakeLists.txt" >&2; exit 1; }

lib="$(installed_library)"
if [[ $force -eq 0 && -n "$lib" ]]; then
    echo "setup_rosco.sh: ROSCO ${version} is already installed in $prefix (use --force to rebuild)"
    report "$lib"
    exit 0
fi

build="$src/rosco/controller/build-gale"
mkdir -p "$build"
echo "setup_rosco.sh: configuring in $build (install prefix $prefix)"
cmake -S "$src/rosco/controller" -B "$build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_Fortran_COMPILER="$(command -v "$fortran")" \
    -DCMAKE_INSTALL_PREFIX="$prefix" > "$build/setup_rosco.configure.log" 2>&1 \
    || { tail -30 "$build/setup_rosco.configure.log" >&2; echo "setup_rosco.sh: configure failed (log: $build/setup_rosco.configure.log)" >&2; exit 1; }
echo "setup_rosco.sh: building with $jobs jobs (log: $build/setup_rosco.build.log)"
cmake --build "$build" -j "$jobs" > "$build/setup_rosco.build.log" 2>&1 \
    || { tail -30 "$build/setup_rosco.build.log" >&2; echo "setup_rosco.sh: build failed" >&2; exit 1; }
cmake --install "$build" > "$build/setup_rosco.install.log" 2>&1 \
    || { tail -30 "$build/setup_rosco.install.log" >&2; echo "setup_rosco.sh: install failed" >&2; exit 1; }
lib="$(installed_library)"
[[ -n "$lib" ]] || { echo "setup_rosco.sh: the install has no lib/libdiscon.so or lib/libdiscon.dylib in $prefix" >&2; exit 1; }
echo "setup_rosco.sh: ROSCO ${version} installed in $prefix"
report "$lib"
