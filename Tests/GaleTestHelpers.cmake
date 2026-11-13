# GALE's copies of ERF's CTest helpers, with the arguments GALE's tests need that ERF's own
# helpers do not have. ERF's general helpers (Submodules/ERF/Tests/ERFTestHelpers.cmake:
# resolve_test_exe, add_test_abort, ...) are included before this file and used as they are.
#
#   gale_setup_test               ERF's setup_test, plus TEST_SOURCE_ROOT: the decks are read from
#                                 ${TEST_SOURCE_ROOT}/<case> (Exec/CanonicalTests/MovingBodies)
#   gale_add_test_r               ERF's add_test_r, through gale_setup_test
#   gale_add_test_restart_abort   ERF's add_test_restart_abort, plus CORRUPT_FILE and CORRUPT_TEXT
#   gale_add_test_box_parity      ERF's add_test_box_parity, plus DATALOG_ZERO_EXPONENT
#   gale_add_test_option_parity   ERF's add_test_option_parity, plus ON_LOG_REGEX, OFF_LOG_REGEX,
#                                 FCOMPARE_RTOL and FCOMPARE_ATOL
#   gale_add_test_restart_parity  ERF's add_test_restart_parity, plus DATALOG_ZERO_EXPONENT and OVERRUN
#
# The drivers they run (RunRestartAbort.cmake, RunBoxParity.cmake, RunOptionParity.cmake,
# RunRestartParity.cmake, CompareDataLogs.cmake) are GALE's copies in this folder. Every driver is
# given ERF_TESTS_DIR, the folder of ERF's MPILauncher.cmake and ResolveExecutable.cmake.

set(GALE_TESTS_DIR "${CMAKE_CURRENT_LIST_DIR}")
set(GALE_ERF_TESTS_DIR "${ERF_SOURCE_DIR}/Tests")

macro(gale_setup_test)
    if(DEFINED TEST_FILES_DIR AND NOT "${TEST_FILES_DIR}" STREQUAL "")
        set(_test_source_dir_name "${TEST_FILES_DIR}")
    else()
        set(_test_source_dir_name "${TEST_NAME}")
    endif()
    # the decks live under GALE's Tests/test_files unless the caller points TEST_SOURCE_ROOT at
    # another tree (the canonical cases under Exec/CanonicalTests/<group>, one directory per case)
    if(DEFINED TEST_SOURCE_ROOT AND NOT "${TEST_SOURCE_ROOT}" STREQUAL "")
        set(CURRENT_TEST_SOURCE_DIR ${TEST_SOURCE_ROOT}/${_test_source_dir_name})
    else()
        set(CURRENT_TEST_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/test_files/${_test_source_dir_name})
    endif()
    set(CURRENT_TEST_BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR}/test_files/${TEST_NAME})
    set(PLOT_GOLD ${ERF_TEST_GOLD_FILES_DIRECTORY}/${TEST_NAME})

    file(MAKE_DIRECTORY ${CURRENT_TEST_BINARY_DIR})
    file(GLOB TEST_FILES "${CURRENT_TEST_SOURCE_DIR}/*")
    file(COPY ${TEST_FILES} DESTINATION "${CURRENT_TEST_BINARY_DIR}/")

    if(ERF_ENABLE_MPI)
        set(NP ${ERF_TEST_NRANKS})
        set(MPI_COMMANDS "${ERF_SH_MPI_LAUNCHER}${MPIEXEC_NUMPROC_FLAG} ${NP} ${MPIEXEC_PREFLAGS}")
        set(MPI_FCOMP_COMMANDS "${ERF_SH_MPI_LAUNCHER}${MPIEXEC_NUMPROC_FLAG} 1 ${MPIEXEC_PREFLAGS}")
    else()
        set(NP 1)
        unset(MPI_COMMANDS)
        unset(MPI_FCOMP_COMMANDS)
    endif()
endmacro(gale_setup_test)

# Standard regression test
function(gale_add_test_r TEST_NAME TEST_DIR TEST_EXE PLTFILE)
    set(options )
    set(oneValueArgs "INPUT_SOUNDING" "RUNTIME_OPTIONS" "FCOMPARE_RTOL" "FCOMPARE_ATOL")
    set(multiValueArgs )
    cmake_parse_arguments(ADD_TEST_R "${options}" "${oneValueArgs}"
        "${multiValueArgs}" ${ARGN})

    # Inputs a parent project may not have set; ERF's own configure always sets them.
    set(_required FCOMPARE_EXE ERF_TEST_GOLD_FILES_DIRECTORY)
    if("${ADD_TEST_R_FCOMPARE_RTOL}" STREQUAL "")
        list(APPEND _required ERF_TEST_FCOMPARE_RTOL)
    endif()
    if("${ADD_TEST_R_FCOMPARE_ATOL}" STREQUAL "")
        list(APPEND _required ERF_TEST_FCOMPARE_ATOL)
    endif()
    if(ERF_ENABLE_MPI)
        list(APPEND _required ERF_TEST_NRANKS)
    endif()
    foreach(_var IN LISTS _required)
        if("${${_var}}" STREQUAL "")
            message(FATAL_ERROR "gale_add_test_r(${TEST_NAME}): ${_var} is empty; see the header of "
                                "Submodules/ERF/Tests/ERFTestHelpers.cmake")
        endif()
    endforeach()

    gale_setup_test()

    set(RUNTIME_OPTIONS "${ADD_TEST_R_RUNTIME_OPTIONS}")
    if(NOT "${ADD_TEST_R_INPUT_SOUNDING}" STREQUAL "")
      string(APPEND RUNTIME_OPTIONS "erf.input_sounding_file=${CURRENT_TEST_BINARY_DIR}/${ADD_TEST_R_INPUT_SOUNDING}")
    endif()

    resolve_test_exe("${TEST_DIR}" "${TEST_EXE}" TEST_EXE)

    set(_fcompare_rtol "${ERF_TEST_FCOMPARE_RTOL}")
    set(_fcompare_atol "${ERF_TEST_FCOMPARE_ATOL}")
    if(NOT "${ADD_TEST_R_FCOMPARE_RTOL}" STREQUAL "")
        set(_fcompare_rtol "${ADD_TEST_R_FCOMPARE_RTOL}")
    endif()
    if(NOT "${ADD_TEST_R_FCOMPARE_ATOL}" STREQUAL "")
        set(_fcompare_atol "${ADD_TEST_R_FCOMPARE_ATOL}")
    endif()

    set(FCOMPARE_TOLERANCE "-r ${_fcompare_rtol} --abs_tol ${_fcompare_atol}")
    set(FCOMPARE_FLAGS "--abort_if_not_all_found -a ${FCOMPARE_TOLERANCE}")
    set(test_command sh -c "${MPI_COMMANDS} ${TEST_EXE} ${CURRENT_TEST_BINARY_DIR}/${TEST_NAME}.i ${RUNTIME_OPTIONS} > ${TEST_NAME}.log && ${MPI_FCOMP_COMMANDS} ${FCOMPARE_EXE} ${FCOMPARE_FLAGS} ${PLOT_GOLD} ${CURRENT_TEST_BINARY_DIR}/${PLTFILE}")

    add_test(NAME ${TEST_NAME} COMMAND ${test_command})
    set_tests_properties(${TEST_NAME}
        PROPERTIES
        TIMEOUT 600
        PROCESSORS ${NP}
        WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
        LABELS "regression"
        ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/${TEST_NAME}.log"
    )
endfunction(gale_add_test_r)

# Restart abort: run a deck to a checkpoint, restart from it, and require the restart to stop
# with EXPECTED_MESSAGE. For guards that only a restart can reach, which add_test_abort cannot
# test because it runs a single leg and no checkpoint exists yet.  CHK_NRANKS and
# RESTART_NRANKS are separate so a test can reproduce a restart on more ranks than the
# checkpoint was written with, which is its own code path.
function(gale_add_test_restart_abort TEST_NAME TEST_FILES_DIR STEP_CHK EXPECTED_MESSAGE)
    set(oneValueArgs "COMMON_OPTIONS" "RESTART_OPTIONS" "CHK_NRANKS" "RESTART_NRANKS" "RUN_TIMEOUT" "CORRUPT_FILE" "CORRUPT_TEXT")
    cmake_parse_arguments(ADD_TEST_RA "" "${oneValueArgs}" "" ${ARGN})
    gale_setup_test()
    if(DEFINED ERF_TEST_EXE AND NOT "${ERF_TEST_EXE}" STREQUAL "")
        resolve_test_exe("" "${ERF_TEST_EXE}" TEST_EXE)
    else()
        resolve_test_exe("" "erf_exec" TEST_EXE)
    endif()

    set(_chk_nranks "${NP}")
    set(_restart_nranks "${NP}")
    if(NOT "${ADD_TEST_RA_CHK_NRANKS}" STREQUAL "")
        set(_chk_nranks "${ADD_TEST_RA_CHK_NRANKS}")
    endif()
    if(NOT "${ADD_TEST_RA_RESTART_NRANKS}" STREQUAL "")
        set(_restart_nranks "${ADD_TEST_RA_RESTART_NRANKS}")
    endif()
    set(_run_timeout 600)
    set(_ctest_timeout 600)
    if(DEFINED ADD_TEST_RA_RUN_TIMEOUT)
        set(_run_timeout "${ADD_TEST_RA_RUN_TIMEOUT}")
        math(EXPR _ctest_timeout "2 * ${_run_timeout} + 600")
    endif()
    # The watchdog has to cover both legs, and the processor reservation the wider leg.
    set(_procs "${_chk_nranks}")
    if(_restart_nranks GREATER _procs)
        set(_procs "${_restart_nranks}")
    endif()

    add_test(NAME ${TEST_NAME} COMMAND ${CMAKE_COMMAND}
        "-DMPIEXEC=${MPIEXEC_EXECUTABLE}"
        "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
        "-DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
        "-DCHK_NRANKS=${_chk_nranks}"
        "-DRESTART_NRANKS=${_restart_nranks}"
        "-DTEST_EXE=${TEST_EXE}"
        "-DCONFIG=$<CONFIG>"
        "-DINPUT=${CURRENT_TEST_BINARY_DIR}/${TEST_FILES_DIR}.i"
        "-DWORKING_DIRECTORY=${CURRENT_TEST_BINARY_DIR}"
        "-DSTEP_CHK=${STEP_CHK}"
        "-DEXPECTED_MESSAGE=${EXPECTED_MESSAGE}"
        "-DRUN_TIMEOUT=${_run_timeout}"
        "-DCOMMON_OPTIONS=${ADD_TEST_RA_COMMON_OPTIONS}"
        "-DRESTART_OPTIONS=${ADD_TEST_RA_RESTART_OPTIONS}"
        "-DCORRUPT_FILE=${ADD_TEST_RA_CORRUPT_FILE}"
        "-DCORRUPT_TEXT=${ADD_TEST_RA_CORRUPT_TEXT}"
        "-DERF_TESTS_DIR=${GALE_ERF_TESTS_DIR}"
        -P ${GALE_TESTS_DIR}/RunRestartAbort.cmake)
    set_tests_properties(${TEST_NAME}
        PROPERTIES
        TIMEOUT ${_ctest_timeout}
        PROCESSORS ${_procs}
        WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
        LABELS "regression;restart-parity"
        ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/run/checkpoint.log;${CURRENT_TEST_BINARY_DIR}/run/restart.log")
endfunction(gale_add_test_restart_abort)

# Run the deck in test_files/<TEST_FILES_DIR> on a single box (one rank) and on a split
# BoxArray (ERF_TEST_NRANKS ranks) and compare the two plotfiles PLTFILE with fcompare.
# COMMON_OPTIONS go to both runs, REFERENCE_OPTIONS must make the grid a single box and
# SPLIT_OPTIONS give the split (the deck's own grid when empty).
function(gale_add_test_box_parity TEST_NAME TEST_FILES_DIR PLTFILE)
    set(oneValueArgs "COMMON_OPTIONS" "REFERENCE_OPTIONS" "SPLIT_OPTIONS" "FCOMPARE_RTOL" "FCOMPARE_ATOL" "DATALOG" "DATALOG_SIGDIGITS" "DATALOG_ZERO_EXPONENT")
    cmake_parse_arguments(ADD_TEST_BP "" "${oneValueArgs}" "" ${ARGN})
    gale_setup_test()
    resolve_test_exe("" "erf_exec" TEST_EXE)

    set(_fcompare_rtol "${ERF_TEST_FCOMPARE_RTOL}")
    set(_fcompare_atol "${ERF_TEST_FCOMPARE_ATOL}")
    if(NOT "${ADD_TEST_BP_FCOMPARE_RTOL}" STREQUAL "")
        set(_fcompare_rtol "${ADD_TEST_BP_FCOMPARE_RTOL}")
    endif()
    if(NOT "${ADD_TEST_BP_FCOMPARE_ATOL}" STREQUAL "")
        set(_fcompare_atol "${ADD_TEST_BP_FCOMPARE_ATOL}")
    endif()

    add_test(NAME ${TEST_NAME} COMMAND ${CMAKE_COMMAND}
        "-DMPIEXEC=${MPIEXEC_EXECUTABLE}"
        "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
        "-DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
        "-DNRANKS=${NP}"
        "-DTEST_EXE=${TEST_EXE}"
        "-DCONFIG=$<CONFIG>"
        "-DINPUT=${CURRENT_TEST_BINARY_DIR}/${TEST_FILES_DIR}.i"
        "-DWORKING_DIRECTORY=${CURRENT_TEST_BINARY_DIR}"
        "-DFCOMPARE=${FCOMPARE_EXE}"
        "-DPLTFILE=${PLTFILE}"
        "-DRTOL=${_fcompare_rtol}"
        "-DATOL=${_fcompare_atol}"
        "-DCOMMON_OPTIONS=${ADD_TEST_BP_COMMON_OPTIONS}"
        "-DREFERENCE_OPTIONS=${ADD_TEST_BP_REFERENCE_OPTIONS}"
        "-DSPLIT_OPTIONS=${ADD_TEST_BP_SPLIT_OPTIONS}"
        "-DDATALOG=${ADD_TEST_BP_DATALOG}"
        "-DDATALOG_SIGDIGITS=${ADD_TEST_BP_DATALOG_SIGDIGITS}"
        "-DDATALOG_ZERO_EXPONENT=${ADD_TEST_BP_DATALOG_ZERO_EXPONENT}"
        "-DERF_TESTS_DIR=${GALE_ERF_TESTS_DIR}"
        -P ${GALE_TESTS_DIR}/RunBoxParity.cmake)
    set_tests_properties(${TEST_NAME}
        PROPERTIES
        TIMEOUT 600
        PROCESSORS ${NP}
        WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
        LABELS "regression;box-parity"
        ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/one_box/simulation.log;${CURRENT_TEST_BINARY_DIR}/split/simulation.log;${CURRENT_TEST_BINARY_DIR}/parity.log")
endfunction(gale_add_test_box_parity)

# Run the deck in test_files/<TEST_FILES_DIR> twice, once with a diagnostic off and once
# with it on, and require PLTFILE to be identical bit for bit.  This is the harness for
# "turning this output on does not change the answer": OFF_OPTIONS and ON_OPTIONS are the
# two option sets, COMMON_OPTIONS go to both, and REQUIRE_ON_FILE names a file the on leg
# must write and the off leg must not, so a misspelled option cannot pass as agreement.
# ON_LOG_REGEX does the same through the legs' simulation.log (and OFF_LOG_REGEX must match the off
# leg's only), and FCOMPARE_RTOL and FCOMPARE_ATOL replace the zero tolerances for an option that
# changes only the order of a sum.
function(gale_add_test_option_parity TEST_NAME TEST_FILES_DIR PLTFILE)
    set(oneValueArgs "COMMON_OPTIONS" "OFF_OPTIONS" "ON_OPTIONS" "REQUIRE_ON_FILE" "RUN_TIMEOUT" "ON_LOG_REGEX" "OFF_LOG_REGEX" "FCOMPARE_RTOL" "FCOMPARE_ATOL")
    cmake_parse_arguments(ADD_TEST_OP "" "${oneValueArgs}" "" ${ARGN})
    gale_setup_test()
    resolve_test_exe("" "erf_exec" TEST_EXE)

    set(_run_timeout 600)
    set(_ctest_timeout 600)
    if(DEFINED ADD_TEST_OP_RUN_TIMEOUT)
        set(_run_timeout "${ADD_TEST_OP_RUN_TIMEOUT}")
        math(EXPR _ctest_timeout "2 * ${_run_timeout} + 600")
    endif()

    add_test(NAME ${TEST_NAME} COMMAND ${CMAKE_COMMAND}
        "-DMPIEXEC=${MPIEXEC_EXECUTABLE}"
        "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
        "-DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
        "-DNRANKS=${NP}"
        "-DTEST_EXE=${TEST_EXE}"
        "-DCONFIG=$<CONFIG>"
        "-DINPUT=${CURRENT_TEST_BINARY_DIR}/${TEST_FILES_DIR}.i"
        "-DWORKING_DIRECTORY=${CURRENT_TEST_BINARY_DIR}"
        "-DFCOMPARE=${FCOMPARE_EXE}"
        "-DPLTFILE=${PLTFILE}"
        "-DRUN_TIMEOUT=${_run_timeout}"
        "-DCOMMON_OPTIONS=${ADD_TEST_OP_COMMON_OPTIONS}"
        "-DOFF_OPTIONS=${ADD_TEST_OP_OFF_OPTIONS}"
        "-DON_OPTIONS=${ADD_TEST_OP_ON_OPTIONS}"
        "-DREQUIRE_ON_FILE=${ADD_TEST_OP_REQUIRE_ON_FILE}"
        "-DON_LOG_REGEX=${ADD_TEST_OP_ON_LOG_REGEX}"
        "-DOFF_LOG_REGEX=${ADD_TEST_OP_OFF_LOG_REGEX}"
        "-DRTOL=${ADD_TEST_OP_FCOMPARE_RTOL}"
        "-DATOL=${ADD_TEST_OP_FCOMPARE_ATOL}"
        "-DERF_TESTS_DIR=${GALE_ERF_TESTS_DIR}"
        -P ${GALE_TESTS_DIR}/RunOptionParity.cmake)
    set_tests_properties(${TEST_NAME}
        PROPERTIES
        TIMEOUT ${_ctest_timeout}
        PROCESSORS ${NP}
        WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
        LABELS "regression;option-parity"
        ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/option_off/simulation.log;${CURRENT_TEST_BINARY_DIR}/option_on/simulation.log;${CURRENT_TEST_BINARY_DIR}/parity.log")
endfunction(gale_add_test_option_parity)

# Restart parity: run one deck straight, then to a checkpoint and on from it, and
# require the plotfile at the end to be identical (no gold file). Every run has a
# time limit; the default stays at 600, but an explicit RUN_TIMEOUT is forwarded
# unchanged to each leg and used to size the outer CTest watchdog.
# COMMON_OPTIONS reaches all three legs; RESTART_OPTIONS reaches the restart leg alone,
# which is where anything that changes the decomposition has to go.  ALLOW_DIFF_GRIDS
# lets fcompare compare plotfiles written on different BoxArrays, which a restart leg
# that re-makes the level-0 grids needs and no other restart test should want.
# CHK_NRANKS/RESTART_NRANKS give the checkpoint and restart legs separate rank counts, for
# the case of continuing a run on more ranks than it was written with; the straight leg
# follows the restart's count so the comparison isolates the restart, not the decomposition.
# REQUIRE_LEVEL0_REMAKE makes a regrid test fail if the restart stopped regridding, which
# would otherwise leave it silently comparing an ordinary restart and passing.
function(gale_add_test_restart_parity TEST_NAME TEST_FILES_DIR STEP_CHK STEP_END)
    set(oneValueArgs "COMMON_OPTIONS" "RESTART_OPTIONS" "CHK_OPTIONS" "CHK_LEG_END" "CHK_NRANKS" "RESTART_NRANKS" "FCOMPARE_RTOL" "FCOMPARE_ATOL" "RUN_TIMEOUT" "DATALOG" "DATALOG_SIGDIGITS" "DATALOG_ZERO_EXPONENT" "PLT2DFILE" "BNDRY_PLANES_DIR" "BNDRY_PLANES_FIRST_STEP" "BNDRY_PLANES_STEPS" "BNDRY_PLANES_READ_INPUT" "CHECKER" "CHECK_MODE" "CHECKER_LOG")
    cmake_parse_arguments(ADD_TEST_RP "ALLOW_DIFF_GRIDS;REQUIRE_LEVEL0_REMAKE;OVERRUN;BNDRY_PLANES_STALE;BNDRY_PLANES_CUT_NEWLINE;BNDRY_PLANES_EARLY_STOP" "${oneValueArgs}" "" ${ARGN})
    gale_setup_test()
    resolve_test_exe("" "erf_exec" TEST_EXE)
    set(_checker_log "")
    set(_post_checkpoint_log "")
    if(NOT "${ADD_TEST_RP_CHECK_MODE}" STREQUAL "")
        if("${ADD_TEST_RP_CHECKER}" STREQUAL "")
            message(FATAL_ERROR "${TEST_NAME}: CHECKER is required when CHECK_MODE is set")
        endif()
        if("${ADD_TEST_RP_CHECKER_LOG}" STREQUAL "")
            set(_checker_log "${CURRENT_TEST_BINARY_DIR}/${TEST_NAME}.checkpoint-activity.log")
        else()
            set(_checker_log "${ADD_TEST_RP_CHECKER_LOG}")
        endif()
        if(ADD_TEST_RP_CHECK_MODE STREQUAL "wdm6_active")
            set(_post_checkpoint_log "${CURRENT_TEST_BINARY_DIR}/post_checkpoint_parity.log")
        endif()
    endif()

    set(_fcompare_rtol "${ERF_TEST_FCOMPARE_RTOL}")
    set(_fcompare_atol "${ERF_TEST_FCOMPARE_ATOL}")
    if(NOT "${ADD_TEST_RP_FCOMPARE_RTOL}" STREQUAL "")
        set(_fcompare_rtol "${ADD_TEST_RP_FCOMPARE_RTOL}")
    endif()
    if(NOT "${ADD_TEST_RP_FCOMPARE_ATOL}" STREQUAL "")
        set(_fcompare_atol "${ADD_TEST_RP_FCOMPARE_ATOL}")
    endif()
    set(_run_timeout 600)
    set(_ctest_timeout 600)
    if(DEFINED ADD_TEST_RP_RUN_TIMEOUT)
        set(_run_timeout "${ADD_TEST_RP_RUN_TIMEOUT}")
        math(EXPR _ctest_timeout "3 * ${_run_timeout} + 600")
    endif()

    add_test(NAME ${TEST_NAME} COMMAND ${CMAKE_COMMAND}
        "-DMPIEXEC=${MPIEXEC_EXECUTABLE}"
        "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
        "-DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
        "-DNRANKS=${NP}"
        "-DTEST_EXE=${TEST_EXE}"
        "-DCONFIG=$<CONFIG>"
        "-DINPUT=${CURRENT_TEST_BINARY_DIR}/${TEST_FILES_DIR}.i"
        "-DWORKING_DIRECTORY=${CURRENT_TEST_BINARY_DIR}"
        "-DFCOMPARE=${FCOMPARE_EXE}"
        "-DSTEP_CHK=${STEP_CHK}"
        "-DSTEP_END=${STEP_END}"
        "-DRTOL=${_fcompare_rtol}"
        "-DATOL=${_fcompare_atol}"
        "-DRUN_TIMEOUT=${_run_timeout}"
        "-DCOMMON_OPTIONS=${ADD_TEST_RP_COMMON_OPTIONS}"
        "-DRESTART_OPTIONS=${ADD_TEST_RP_RESTART_OPTIONS}"
        "-DALLOW_DIFF_GRIDS=${ADD_TEST_RP_ALLOW_DIFF_GRIDS}"
        "-DREQUIRE_LEVEL0_REMAKE=${ADD_TEST_RP_REQUIRE_LEVEL0_REMAKE}"
        "-DCHK_NRANKS=${ADD_TEST_RP_CHK_NRANKS}"
        "-DRESTART_NRANKS=${ADD_TEST_RP_RESTART_NRANKS}"
        "-DDATALOG=${ADD_TEST_RP_DATALOG}"
        "-DDATALOG_SIGDIGITS=${ADD_TEST_RP_DATALOG_SIGDIGITS}"
        "-DDATALOG_ZERO_EXPONENT=${ADD_TEST_RP_DATALOG_ZERO_EXPONENT}"
        "-DPLT2DFILE=${ADD_TEST_RP_PLT2DFILE}"
        "-DOVERRUN=${ADD_TEST_RP_OVERRUN}"
        "-DCHK_OPTIONS=${ADD_TEST_RP_CHK_OPTIONS}"
        "-DCHK_LEG_END=${ADD_TEST_RP_CHK_LEG_END}"
        "-DBNDRY_PLANES_DIR=${ADD_TEST_RP_BNDRY_PLANES_DIR}"
        "-DBNDRY_PLANES_FIRST_STEP=${ADD_TEST_RP_BNDRY_PLANES_FIRST_STEP}"
        "-DBNDRY_PLANES_STALE=${ADD_TEST_RP_BNDRY_PLANES_STALE}"
        "-DBNDRY_PLANES_STEPS=${ADD_TEST_RP_BNDRY_PLANES_STEPS}"
        "-DBNDRY_PLANES_CUT_NEWLINE=${ADD_TEST_RP_BNDRY_PLANES_CUT_NEWLINE}"
        "-DBNDRY_PLANES_EARLY_STOP=${ADD_TEST_RP_BNDRY_PLANES_EARLY_STOP}"
        "-DBNDRY_PLANES_READ_INPUT=${ADD_TEST_RP_BNDRY_PLANES_READ_INPUT}"
        "-DCHECKER=${ADD_TEST_RP_CHECKER}"
        "-DCHECK_MODE=${ADD_TEST_RP_CHECK_MODE}"
        "-DCHECKER_LOG=${_checker_log}"
        "-DERF_TESTS_DIR=${GALE_ERF_TESTS_DIR}"
        -P ${GALE_TESTS_DIR}/RunRestartParity.cmake)
    # The reservation has to cover the widest leg, which need not be NP.
    set(_procs "${NP}")
    foreach(_n "${ADD_TEST_RP_CHK_NRANKS}" "${ADD_TEST_RP_RESTART_NRANKS}")
        if(NOT "${_n}" STREQUAL "" AND _n GREATER _procs)
            set(_procs "${_n}")
        endif()
    endforeach()

    set_tests_properties(${TEST_NAME}
        PROPERTIES
        TIMEOUT ${_ctest_timeout}
        PROCESSORS ${_procs}
        WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
        LABELS "regression;restart-parity"
        ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/straight/simulation.log;${CURRENT_TEST_BINARY_DIR}/restart/checkpoint.log;${CURRENT_TEST_BINARY_DIR}/restart/restart.log;${CURRENT_TEST_BINARY_DIR}/parity.log;${_checker_log};${_post_checkpoint_log}")
endfunction(gale_add_test_restart_parity)
