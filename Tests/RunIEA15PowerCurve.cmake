# Run one deck of Exec/CanonicalTests/MovingBodies/OpenFAST_IEA15_PowerCurve for ten steps at 9 m/s
# with the real OpenFAST library and the ROSCO controller, and check it two ways: the run log must
# show that ServoDyn loaded ROSCO, and the turbine log (T1_erf.csv: rotor speed, thrust, torque,
# power, written every step of the turbine's level) must agree with the committed gold. The run folder is made by the case's prepare.py, so the
# test also covers the script: the model copy, the controller switches and the wind speed.
#
# Variables: MPIEXEC, MPIEXEC_NUMPROC_FLAG, MPIEXEC_PREFLAGS, NRANKS, TEST_EXE, CONFIG, CASE_DIR,
# DECK (adm_20m, adm_10m, alm_10m or alm_5m), LIBDISCON, PYTHON_EXE, WORKING_DIRECTORY,
# TURBINE_GOLD, and optionally SIGDIGITS (default 6) and ZERO_EXPONENT (default -4).

cmake_minimum_required(VERSION 3.20)
include("${CMAKE_CURRENT_LIST_DIR}/MPILauncher.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/ResolveExecutable.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/CompareDataLogs.cmake")

foreach(arg TEST_EXE CASE_DIR DECK LIBDISCON PYTHON_EXE WORKING_DIRECTORY TURBINE_GOLD)
    if(NOT DEFINED ${arg} OR "${${arg}}" STREQUAL "")
        message(FATAL_ERROR "RunIEA15PowerCurve.cmake: ${arg} must be given")
    endif()
endforeach()
if(NOT DEFINED NRANKS OR "${NRANKS}" STREQUAL "")
    set(NRANKS 1)
endif()
if(NOT DEFINED SIGDIGITS OR "${SIGDIGITS}" STREQUAL "")
    set(SIGDIGITS 6)
endif()
if(NOT DEFINED ZERO_EXPONENT OR "${ZERO_EXPONENT}" STREQUAL "")
    set(ZERO_EXPONENT -4)
endif()
if(NOT EXISTS "${LIBDISCON}")
    message(FATAL_ERROR "RunIEA15PowerCurve.cmake: the ROSCO library ${LIBDISCON} does not exist "
                        "(with ERF_BUILD_ROSCO=ON, build the rosco_controller target first)")
endif()
if(NOT EXISTS "${TURBINE_GOLD}")
    message(FATAL_ERROR "RunIEA15PowerCurve.cmake: no gold ${TURBINE_GOLD}")
endif()

erf_resolve_executable(TEST_EXE "${TEST_EXE}" CONFIG "${CONFIG}"
    CONTEXT "RunIEA15PowerCurve.cmake: ERF executable")
erf_mpi_launcher_command(launcher
    LAUNCHER "${MPIEXEC}"
    NUMPROC_FLAG "${MPIEXEC_NUMPROC_FLAG}"
    NRANKS ${NRANKS}
    PREFLAGS "${MPIEXEC_PREFLAGS}"
    CONTEXT "RunIEA15PowerCurve.cmake")

# ---- the run folder, from the case's own script ----
set(runs "${WORKING_DIRECTORY}/runs")
set(run_dir "${runs}/${DECK}/ws9.0")
file(REMOVE_RECURSE "${runs}")
execute_process(
    COMMAND ${PYTHON_EXE} ${CASE_DIR}/prepare.py --libdiscon ${LIBDISCON} --decks ${DECK} --speeds 9.0 --out ${runs}
    OUTPUT_VARIABLE prep_out
    ERROR_VARIABLE prep_out
    RESULT_VARIABLE prep_result)
if(NOT prep_result EQUAL 0 OR NOT EXISTS "${run_dir}/${DECK}.i")
    message(FATAL_ERROR "RunIEA15PowerCurve.cmake: prepare.py failed (${prep_result}):\n${prep_out}")
endif()

# ---- ten steps ----
set(log "${WORKING_DIRECTORY}/simulation.log")
execute_process(
    COMMAND ${launcher} ${TEST_EXE} ${DECK}.i amrex.call_addr2line=0
            max_step=10 stop_time=2.0 erf.check_int=-1 erf.plot_int_1=-1
            erf.moving_bodies.diagnostics_int=1
    WORKING_DIRECTORY "${run_dir}"
    OUTPUT_FILE "${log}"
    ERROR_FILE "${log}"
    RESULT_VARIABLE result)
file(READ "${log}" contents)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "RunIEA15PowerCurve.cmake: the simulation failed (${result}):\n${contents}")
endif()
if(NOT contents MATCHES "Running ROSCO")
    message(FATAL_ERROR "RunIEA15PowerCurve.cmake: the log has no 'Running ROSCO' line; ServoDyn did not load the controller:\n${contents}")
endif()
if(NOT EXISTS "${run_dir}/T1_erf.csv")
    message(FATAL_ERROR "RunIEA15PowerCurve.cmake: the run wrote no T1_erf.csv")
endif()

# ---- the turbine log against its gold, on the columns the controller acts on ----
set(columns time rotor_speed thrust_x torque power)
function(select_columns in_file out_file)
    file(STRINGS "${in_file}" rows)
    list(LENGTH rows nrows)
    if(nrows LESS 12)
        message(FATAL_ERROR "RunIEA15PowerCurve.cmake: ${in_file} has ${nrows} lines; ten steps write a header, the initial row and at least ten rows")
    endif()
    list(GET rows 0 header)
    string(REPLACE "," ";" names "${header}")
    set(idx "")
    foreach(c IN LISTS columns)
        list(FIND names "${c}" i)
        if(i LESS 0)
            message(FATAL_ERROR "RunIEA15PowerCurve.cmake: ${in_file} has no column ${c}: ${header}")
        endif()
        list(APPEND idx ${i})
    endforeach()
    set(text "")
    foreach(row IN LISTS rows)
        string(REPLACE "," ";" fields "${row}")
        set(kept "")
        foreach(i IN LISTS idx)
            list(GET fields ${i} v)
            list(APPEND kept "${v}")
        endforeach()
        string(JOIN " " line ${kept})
        string(APPEND text "${line}\n")
    endforeach()
    file(WRITE "${out_file}" "${text}")
endfunction()
select_columns("${TURBINE_GOLD}" "${WORKING_DIRECTORY}/turbine_gold_columns.txt")
select_columns("${run_dir}/T1_erf.csv" "${WORKING_DIRECTORY}/turbine_run_columns.txt")
erf_compare_data_logs("${WORKING_DIRECTORY}/turbine_gold_columns.txt" "${WORKING_DIRECTORY}/turbine_run_columns.txt"
                      ${SIGDIGITS} 2 turbine_agrees turbine_message "${ZERO_EXPONENT}")
if(NOT turbine_agrees)
    file(READ "${run_dir}/T1_erf.csv" turbine)
    message(FATAL_ERROR "RunIEA15PowerCurve.cmake: T1_erf.csv differs from its gold: ${turbine_message}\n${turbine}")
endif()
message(STATUS "RunIEA15PowerCurve.cmake: ${DECK} ran ten steps with ROSCO; T1_erf.csv agrees with its gold to ${SIGDIGITS} digits")
