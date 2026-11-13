#!/usr/bin/env bash
#
# run_unit_tests.sh BIN [CMAKE_FILE]
#
# Runs the moving-bodies unit tests in the erf_unit_tests binary BIN: GALE's suites and ERF's own
# moving-bodies suites (Submodules/ERF/Tests/Unit/MovingBodies).
#
# GALE's suites are read from the test files that CMAKE_FILE (default
# Turbines/ERFStructureModel.cmake) builds into erf_unit_tests, so a new GALE test file or suite
# is run without editing this script. Files that only go into erf_parallel_tests (Tests/
# CMakeLists.txt, ModelFacts) are not listed there and are run by ctest in the MPI jobs.
#
# Before running, it lists the tests the filter selects and fails if any GALE suite is missing:
# googletest exits 0 when a filter selects nothing, so a GALE test file that stops being linked
# into erf_unit_tests would otherwise pass unnoticed.

set -eu -o pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: $0 BIN [CMAKE_FILE]" >&2
    exit 2
fi
bin=$1
cmake_file=${2:-Turbines/ERFStructureModel.cmake}
gale_src=$(dirname "${cmake_file}")/Tests/Unit
erf_src=Submodules/ERF/Tests/Unit/MovingBodies

suites_in() {
    # TEST(Suite, Name), TEST (Suite, Name) and TEST_F(Suite, Name), one suite per line
    grep -hoE '^[[:space:]]*TEST(_F)?[[:space:]]*\([[:space:]]*[A-Za-z_][A-Za-z0-9_]*' "$@" \
        | sed -E 's/.*\([[:space:]]*//' | sort -u
}

gale_files=$(grep -oE '\$\{_dir\}/ERF_GTest[A-Za-z0-9_]+\.cpp' "${cmake_file}" \
    | sed "s|^\${_dir}|${gale_src}|" | sort -u)
if [ -z "${gale_files}" ]; then
    echo "::error::No unit-test files found in ${cmake_file}"
    exit 1
fi
# shellcheck disable=SC2086  # one file name per word
gale_suites=$(suites_in ${gale_files})
if [ -z "${gale_suites}" ]; then
    echo "::error::No unit-test suites found in the files ${cmake_file} lists"
    exit 1
fi
erf_suites=""
if [ -d "${erf_src}" ]; then
    erf_suites=$(suites_in "${erf_src}"/*.cpp)
fi

filter=$(printf '%s\n%s\n' "${gale_suites}" "${erf_suites}" | sed '/^$/d' | sort -u \
    | sed 's/$/.*/' | paste -sd: -)
echo "Filter: ${filter}"

# "Suite." lines name the selected suites; strip the CR of a Windows console
listed=$("${bin}" --gtest_list_tests --gtest_filter="${filter}" | tr -d '\r' \
    | sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)\.$/\1/p' | sort -u)

missing=""
for s in ${gale_suites}; do
    if ! printf '%s\n' "${listed}" | grep -qx "${s}"; then
        missing="${missing} ${s}"
    fi
done
if [ -n "${missing}" ]; then
    echo "::error::GALE unit-test suites not linked into ${bin}:${missing}"
    exit 1
fi
echo "GALE suites found: $(printf '%s\n' "${gale_suites}" | wc -l | tr -d ' ')"

"${bin}" --gtest_filter="${filter}"
