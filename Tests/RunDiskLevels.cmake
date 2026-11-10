# Run a prescribed-Ct disk deck on one level and its twin on two levels (the disk on the fine level,
# whose box is tight around it), each in its own directory, and require the two disks' induction to
# agree (check_levels.py in the case directory): the coarse level must carry the disk's force too.
#
# Variables: MPIEXEC, MPIEXEC_NUMPROC_FLAG, MPIEXEC_PREFLAGS, NRANKS, TEST_EXE, CONFIG, PYTHON,
# WORKING_DIRECTORY, INPUT_ONE, INPUT_TWO, CHECKER, U_FREE, TOL.

cmake_minimum_required(VERSION 3.20)
include("${CMAKE_CURRENT_LIST_DIR}/MPILauncher.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/ResolveExecutable.cmake")

foreach(arg TEST_EXE PYTHON WORKING_DIRECTORY INPUT_ONE INPUT_TWO CHECKER U_FREE TOL)
    if(NOT DEFINED ${arg} OR "${${arg}}" STREQUAL "")
        message(FATAL_ERROR "RunDiskLevels.cmake: ${arg} must be given")
    endif()
endforeach()
if(NOT DEFINED NRANKS OR "${NRANKS}" STREQUAL "")
    set(NRANKS 1)
endif()
erf_resolve_executable(TEST_EXE "${TEST_EXE}" CONFIG "${CONFIG}" CONTEXT "RunDiskLevels.cmake: ERF executable")
erf_mpi_launcher_command(launcher
    LAUNCHER "${MPIEXEC}"
    NUMPROC_FLAG "${MPIEXEC_NUMPROC_FLAG}"
    NRANKS ${NRANKS}
    PREFLAGS "${MPIEXEC_PREFLAGS}"
    CONTEXT "RunDiskLevels.cmake")

foreach(leg one two)
    if(leg STREQUAL "one")
        set(input "${INPUT_ONE}")
    else()
        set(input "${INPUT_TWO}")
    endif()
    set(dir "${WORKING_DIRECTORY}/${leg}")
    file(REMOVE_RECURSE "${dir}")
    file(MAKE_DIRECTORY "${dir}")
    execute_process(
        COMMAND ${launcher} ${TEST_EXE} ${input} amrex.call_addr2line=0
        WORKING_DIRECTORY "${dir}"
        OUTPUT_FILE "${dir}/simulation.log"
        ERROR_FILE "${dir}/simulation.log"
        RESULT_VARIABLE result)
    if(NOT result EQUAL 0)
        file(READ "${dir}/simulation.log" contents)
        message(FATAL_ERROR "RunDiskLevels.cmake: the ${leg}-level run failed (${result}):\n${contents}")
    endif()
endforeach()

execute_process(
    COMMAND ${PYTHON} ${CHECKER} "${WORKING_DIRECTORY}/one/D1_disk.csv" "${WORKING_DIRECTORY}/two/D1_disk.csv" ${U_FREE} ${TOL}
    OUTPUT_VARIABLE out
    ERROR_VARIABLE out
    RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "RunDiskLevels.cmake: the two-level disk's induction differs from the one-level disk's:\n${out}")
endif()
message(STATUS "RunDiskLevels.cmake: ${out}")
