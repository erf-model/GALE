#!/usr/bin/env bash
#
# build_report.sh LOG SCOPE
#
# Lists the compiler diagnostics in the build log LOG, sorted into three groups, and fails if any
# counted group is not empty:
#
#   GALE       diagnostics in a source file outside Submodules/ERF
#   ERF        diagnostics in a source file under Submodules/ERF
#   toolchain  diagnostics with no source file: compiler-driver and linker lines
#              ("clang++: warning: argument unused ..."), and MSVC lines about nvcc's temporary
#              files (tmpxft_*)
#
#   SCOPE = gale       counts GALE only; ERF and toolchain lines are listed, not counted
#   SCOPE = gale-erf   counts all three groups
#
# Diagnostics from AMReX and googletest, in the source tree or in the build tree, are never listed,
# as in ERF's CI. GCC, Clang, nvcc, hipcc and icpx print "warning:" or "warning #"; MSVC prints
# "warning C4244". MSVC linker (LNK4xxx) and command-line (D9xxx) warnings are not matched.
#
# When run in GitHub Actions, the three counts are also written to the step summary.

set -eu -o pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 LOG gale|gale-erf" >&2
    exit 2
fi
log=$1
scope=$2
case "${scope}" in
    gale|gale-erf) ;;
    *) echo "::error::build_report.sh: SCOPE must be gale or gale-erf, not '${scope}'"; exit 2 ;;
esac
if [ ! -r "${log}" ]; then
    echo "::error::Missing or unreadable build log: ${log}"
    exit 1
fi

diag='warning:|warning #|error:|error #|warning C[0-9]+|error C[0-9]+'
# Both slash directions, for the Windows logs
third_party='[/\\]Submodules[/\\](AMReX|amrex|googletest)[/\\]'
erf='Submodules[/\\]ERF[/\\]'
# A diagnostic in a source file names it as file.cpp:12: (GCC, Clang) or file.cpp(12): (MSVC, nvcc)
source_file='\.(cpp|cxx|cc|cu|H|h|hpp|hxx)(:[0-9]|\([0-9])'
nvcc_temp='tmpxft_'

all=$(grep -Ei "${diag}" "${log}" | grep -Ev "${third_party}" | grep -Ev "lto-wrapper: warning:" | sort -u || true)
in_file=$(printf '%s\n' "${all}" | grep -E "${source_file}" | grep -Ev "${nvcc_temp}" || true)
toolchain=$( { printf '%s\n' "${all}" | grep -Ev "${source_file}"; printf '%s\n' "${all}" | grep -E "${nvcc_temp}"; } \
    | sed '/^$/d' | sort -u || true)
gale=$(printf '%s\n' "${in_file}" | grep -Ev "${erf}" | sed '/^$/d' || true)
erf_only=$(printf '%s\n' "${in_file}" | grep -E "${erf}" || true)

count() { printf '%s\n' "$1" | sed '/^$/d' | wc -l | tr -d ' '; }
n_gale=$(count "${gale}")
n_erf=$(count "${erf_only}")
n_tool=$(count "${toolchain}")

if [ -n "${toolchain}" ]; then
    echo "Diagnostics from the toolchain (no source file):"
    printf '%s\n' "${toolchain}"
fi
if [ -n "${erf_only}" ]; then
    echo "Diagnostics from ERF (Submodules/ERF):"
    printf '%s\n' "${erf_only}"
fi
if [ -n "${gale}" ]; then
    echo "Diagnostics from GALE:"
    printf '%s\n' "${gale}"
fi

if [ "${scope}" = gale ]; then other="listed, not counted"; else other="counted"; fi
summary=$(printf 'GALE diagnostics: %s\nERF diagnostics: %s (%s)\nToolchain diagnostics: %s (%s)\n' \
    "${n_gale}" "${n_erf}" "${other}" "${n_tool}" "${other}")
printf '%s\n' "${summary}"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '### Build diagnostics (scope %s)\n\n```\n%s\n```\n' "${scope}" "${summary}" >> "${GITHUB_STEP_SUMMARY}"
fi

if [ "${n_gale}" -ne 0 ]; then
    exit 1
fi
if [ "${scope}" = gale-erf ] && [ $((n_erf + n_tool)) -ne 0 ]; then
    exit 1
fi
