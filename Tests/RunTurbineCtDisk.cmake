# Run the Actuator_TurbineCtDisk deck (one disk on a turbine table, one with a constant Ct) and
# check it two ways: each disk log against its committed gold, and check_turbine_disk.py, which
# reads the turbine table itself and requires the logged Ct, power and thrust to follow it.
#
# Variables: MPIEXEC, MPIEXEC_NUMPROC_FLAG, MPIEXEC_PREFLAGS, NRANKS, TEST_EXE, CONFIG, PYTHON, INPUT,
# WORKING_DIRECTORY, CHECKER, TABLE, SOURCE_DIR (holding the gold logs), SIGDIGITS, ERF_TESTS_DIR.

cmake_minimum_required(VERSION 3.20)
if(NOT ERF_TESTS_DIR OR NOT EXISTS "${ERF_TESTS_DIR}/MPILauncher.cmake")
    message(FATAL_ERROR "ERF_TESTS_DIR must name ERF's Tests folder (Submodules/ERF/Tests), not '${ERF_TESTS_DIR}'")
endif()
include("${ERF_TESTS_DIR}/MPILauncher.cmake")
include("${ERF_TESTS_DIR}/ResolveExecutable.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/CompareDataLogs.cmake")

foreach(arg TEST_EXE PYTHON INPUT WORKING_DIRECTORY CHECKER TABLE SOURCE_DIR)
    if(NOT DEFINED ${arg} OR "${${arg}}" STREQUAL "")
        message(FATAL_ERROR "RunTurbineCtDisk.cmake: ${arg} must be given")
    endif()
endforeach()
if(NOT DEFINED NRANKS OR "${NRANKS}" STREQUAL "")
    set(NRANKS 1)
endif()
if(NOT DEFINED SIGDIGITS OR "${SIGDIGITS}" STREQUAL "")
    set(SIGDIGITS 10)
endif()
erf_resolve_executable(TEST_EXE "${TEST_EXE}" CONFIG "${CONFIG}" CONTEXT "RunTurbineCtDisk.cmake: ERF executable")
erf_mpi_launcher_command(launcher
    LAUNCHER "${MPIEXEC}"
    NUMPROC_FLAG "${MPIEXEC_NUMPROC_FLAG}"
    NRANKS ${NRANKS}
    PREFLAGS "${MPIEXEC_PREFLAGS}"
    CONTEXT "RunTurbineCtDisk.cmake")

set(log "${WORKING_DIRECTORY}/simulation.log")
file(REMOVE "${WORKING_DIRECTORY}/T1_disk.csv" "${WORKING_DIRECTORY}/D1_disk.csv")
execute_process(
    COMMAND ${launcher} ${TEST_EXE} ${INPUT} amrex.call_addr2line=0
    WORKING_DIRECTORY "${WORKING_DIRECTORY}"
    OUTPUT_FILE "${log}"
    ERROR_FILE "${log}"
    RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    file(READ "${log}" contents)
    message(FATAL_ERROR "RunTurbineCtDisk.cmake: the simulation failed (${result}):\n${contents}")
endif()

foreach(csv T1_disk.csv D1_disk.csv)
    if(NOT EXISTS "${WORKING_DIRECTORY}/${csv}")
        message(FATAL_ERROR "RunTurbineCtDisk.cmake: the run wrote no ${csv}")
    endif()
    erf_compare_data_logs("${SOURCE_DIR}/${csv}.gold" "${WORKING_DIRECTORY}/${csv}" ${SIGDIGITS} 2 logs_agree log_message)
    if(NOT logs_agree)
        file(READ "${WORKING_DIRECTORY}/${csv}" contents)
        message(FATAL_ERROR "RunTurbineCtDisk.cmake: ${csv} differs from the gold log: ${log_message}\n${contents}")
    endif()
endforeach()

execute_process(
    COMMAND ${PYTHON} ${CHECKER} ${WORKING_DIRECTORY}/T1_disk.csv ${TABLE} ${WORKING_DIRECTORY}/D1_disk.csv 0.75 1.0
    OUTPUT_VARIABLE out
    ERROR_VARIABLE out
    RESULT_VARIABLE rc)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "RunTurbineCtDisk.cmake: check_turbine_disk.py failed (${rc}):\n${out}")
endif()
message(STATUS "RunTurbineCtDisk.cmake: both disk logs match their golds; ${out}")
