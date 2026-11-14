# The CTests of GALE's turbine model (structure model "gale", Turbines/). GALE's Tests/CMakeLists.txt
# includes this file after ERF's general test helpers (Submodules/ERF/Tests/ERFTestHelpers.cmake) and
# GALE's copies of the helpers that take more arguments (Tests/GaleTestHelpers.cmake, the gale_*
# functions), so CMAKE_CURRENT_SOURCE_DIR and CMAKE_CURRENT_BINARY_DIR are those of GALE's Tests/.
# PROJECT_SOURCE_DIR is GALE's root; ERF_SOURCE_DIR is ERF's (the submodule).

# The moving-bodies cases live in Exec/CanonicalTests/MovingBodies, one directory per case
# (deck, stub turbine file and gold logs); their gold plotfiles stay in Tests/ERFGoldFiles.
set(TEST_SOURCE_ROOT ${PROJECT_SOURCE_DIR}/Exec/CanonicalTests/MovingBodies)
if(ERF_ENABLE_OPENFAST AND ERF_OPENFAST_USE_STUB AND ERF_ENABLE_FFT)
  # The OpenFAST driver steps a stub turbine through a uniform anelastic flow (FFT solver)
  # without adding any forcing (mode = none); the gold plotfile is the same deck run without
  # moving bodies, so the flow must come out unchanged. With MPI the turbine's own log is
  # checked as well, below, since the plotfile alone passes even if the driver never ran.
  if(NOT (ERF_ENABLE_MPI AND NOT WIN32))
    gale_add_test_r(OpenFAST_DriverOnly "" "erf_exec" "plt00005")
  endif()
endif()

# Run a moving-bodies deck in test_files/<CASE> for one step on NRANKS ranks with OPTIONS and require it to end
# with the expected exit code (an optional sixth argument: default 0, a normal end; nonzero for any failure, an
# abort) and output matching REGEX (Tests/RunExpectExit.cmake): the owner ranks of the turbines and disks, and
# the ranks their points reach, that other tests rely on.
function(add_test_moving_bodies_owners TEST_NAME CASE NRANKS OPTIONS REGEX)
    set(_result 0)
    if(ARGC GREATER 5)
        set(_result ${ARGV5})
    endif()
    set(_dir ${CMAKE_CURRENT_BINARY_DIR}/test_files/${TEST_NAME})
    file(MAKE_DIRECTORY ${_dir})
    file(GLOB _files "${TEST_SOURCE_ROOT}/${CASE}/*")
    file(COPY ${_files} DESTINATION "${_dir}/")
    resolve_test_exe("" "erf_exec" TEST_EXE)
    separate_arguments(_opts UNIX_COMMAND "${OPTIONS}")
    separate_arguments(_pre UNIX_COMMAND "${MPIEXEC_PREFLAGS}")
    set(_cmd ${MPIEXEC_EXECUTABLE} ${MPIEXEC_NUMPROC_FLAG} ${NRANKS} ${_pre} ${TEST_EXE} ${_dir}/${CASE}.i
             max_step=1 erf.plot_int_1=-1 erf.plot_int_2=-1 erf.check_int=-1 amrex.call_addr2line=0 ${_opts})
    add_test(NAME ${TEST_NAME}
        COMMAND ${CMAKE_COMMAND}
            "-DCHECK_COMMAND=${_cmd}"
            "-DEXPECTED_RESULT=${_result}"
            "-DEXPECTED_REGEX=${REGEX}"
            -P ${PROJECT_SOURCE_DIR}/Tests/RunExpectExit.cmake)
    set_tests_properties(${TEST_NAME} PROPERTIES
        LABELS "regression;moving-bodies" TIMEOUT 600 PROCESSORS ${NRANKS} WORKING_DIRECTORY "${_dir}/")
endfunction()

# The bodies' logs in another erf.moving_bodies.diagnostics_format (per_rank or farm) against the
# per_turbine files: one deck run in both formats, each body's rows picked out of the rank or farm
# files by their body column must equal its own files (Tests/RunDiagnosticsFormat.cmake). LOGS lists
# body/log pairs; EXTRA_LOGS the run's own files, which must not change with the format.
# A restart cuts the logs back to the checkpoint, each on the rank that writes it (Tests/RunTrimOnRestart.cmake):
# FILES must hold a straight run's bytes after the restart, and TRIMMED_BY names the rank that cuts each file.
function(add_test_trim_on_restart TEST_NAME TEST_FILES_DIR STEP_CHK CHK_LEG_END CHK_NRANKS RESTART_NRANKS)
    set(oneValueArgs "COMMON_OPTIONS" "FILES" "TRIMMED_BY")
    cmake_parse_arguments(ADD_TEST_TF "" "${oneValueArgs}" "" ${ARGN})
    gale_setup_test()
    resolve_test_exe("" "erf_exec" TEST_EXE)
    add_test(NAME ${TEST_NAME} COMMAND ${CMAKE_COMMAND}
        "-DMPIEXEC=${MPIEXEC_EXECUTABLE}"
        "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
        "-DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
        "-DTEST_EXE=${TEST_EXE}"
        "-DCONFIG=$<CONFIG>"
        "-DINPUT=${CURRENT_TEST_BINARY_DIR}/${TEST_FILES_DIR}.i"
        "-DWORKING_DIRECTORY=${CURRENT_TEST_BINARY_DIR}"
        "-DRUN_TIMEOUT=600"
        "-DSTEP_CHK=${STEP_CHK}"
        "-DCHK_LEG_END=${CHK_LEG_END}"
        "-DCHK_NRANKS=${CHK_NRANKS}"
        "-DRESTART_NRANKS=${RESTART_NRANKS}"
        "-DCOMMON_OPTIONS=${ADD_TEST_TF_COMMON_OPTIONS}"
        "-DFILES=${ADD_TEST_TF_FILES}"
        "-DTRIMMED_BY=${ADD_TEST_TF_TRIMMED_BY}"
        "-DERF_TESTS_DIR=${ERF_SOURCE_DIR}/Tests"
        -P ${PROJECT_SOURCE_DIR}/Tests/RunTrimOnRestart.cmake)
    set_tests_properties(${TEST_NAME} PROPERTIES
        LABELS "regression;moving-bodies;restart-parity" TIMEOUT 1800 PROCESSORS ${CHK_NRANKS} WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
        ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/run/simulation.log;${CURRENT_TEST_BINARY_DIR}/run/restart.log")
endfunction()

# The same deck with two settings that change how the bodies' files are written, never what they hold at
# the end (Tests/RunSameLogs.cmake): every file in FILES must hold the same bytes after both runs.
function(add_test_same_logs TEST_NAME TEST_FILES_DIR NRANKS)
    set(oneValueArgs "COMMON_OPTIONS" "OPTIONS_A" "OPTIONS_B" "FILES" "EXPECT_B")
    cmake_parse_arguments(ADD_TEST_SL "" "${oneValueArgs}" "" ${ARGN})
    gale_setup_test()
    resolve_test_exe("" "erf_exec" TEST_EXE)
    add_test(NAME ${TEST_NAME} COMMAND ${CMAKE_COMMAND}
        "-DMPIEXEC=${MPIEXEC_EXECUTABLE}"
        "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
        "-DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
        "-DNRANKS=${NRANKS}"
        "-DTEST_EXE=${TEST_EXE}"
        "-DCONFIG=$<CONFIG>"
        "-DINPUT=${CURRENT_TEST_BINARY_DIR}/${TEST_FILES_DIR}.i"
        "-DWORKING_DIRECTORY=${CURRENT_TEST_BINARY_DIR}"
        "-DRUN_TIMEOUT=600"
        "-DCOMMON_OPTIONS=${ADD_TEST_SL_COMMON_OPTIONS}"
        "-DOPTIONS_A=${ADD_TEST_SL_OPTIONS_A}"
        "-DOPTIONS_B=${ADD_TEST_SL_OPTIONS_B}"
        "-DFILES=${ADD_TEST_SL_FILES}"
        "-DEXPECT_B=${ADD_TEST_SL_EXPECT_B}"
        "-DERF_TESTS_DIR=${ERF_SOURCE_DIR}/Tests"
        -P ${PROJECT_SOURCE_DIR}/Tests/RunSameLogs.cmake)
    set_tests_properties(${TEST_NAME} PROPERTIES
        LABELS "regression;moving-bodies" TIMEOUT 1800 PROCESSORS ${NRANKS} WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
        ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/run_a/simulation.log;${CURRENT_TEST_BINARY_DIR}/run_b/simulation.log")
endfunction()

function(add_test_diagnostics_format TEST_NAME TEST_FILES_DIR FORMAT)
    set(oneValueArgs "COMMON_OPTIONS" "LOGS" "EXTRA_LOGS")
    cmake_parse_arguments(ADD_TEST_DF "" "${oneValueArgs}" "" ${ARGN})
    gale_setup_test()
    resolve_test_exe("" "erf_exec" TEST_EXE)
    add_test(NAME ${TEST_NAME} COMMAND ${CMAKE_COMMAND}
        "-DMPIEXEC=${MPIEXEC_EXECUTABLE}"
        "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
        "-DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
        "-DNRANKS=${NP}"
        "-DTEST_EXE=${TEST_EXE}"
        "-DCONFIG=$<CONFIG>"
        "-DINPUT=${CURRENT_TEST_BINARY_DIR}/${TEST_FILES_DIR}.i"
        "-DWORKING_DIRECTORY=${CURRENT_TEST_BINARY_DIR}"
        "-DRUN_TIMEOUT=600"
        "-DFORMAT=${FORMAT}"
        "-DDIAG_DIR=moving_bodies"
        "-DCOMMON_OPTIONS=${ADD_TEST_DF_COMMON_OPTIONS}"
        "-DLOGS=${ADD_TEST_DF_LOGS}"
        "-DEXTRA_LOGS=${ADD_TEST_DF_EXTRA_LOGS}"
        "-DERF_TESTS_DIR=${ERF_SOURCE_DIR}/Tests"
        -P ${PROJECT_SOURCE_DIR}/Tests/RunDiagnosticsFormat.cmake)
    set_tests_properties(${TEST_NAME} PROPERTIES
        LABELS "regression;moving-bodies" TIMEOUT 1800 PROCESSORS ${NP} WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
        ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/per_turbine/simulation.log;${CURRENT_TEST_BINARY_DIR}/${FORMAT}/simulation.log")
endfunction()

if(ERF_ENABLE_OPENFAST AND ERF_OPENFAST_USE_STUB AND ERF_ENABLE_FFT AND ERF_ENABLE_MPI AND NOT WIN32)
  # The velocity at the stub turbine's nodes is sampled from a linear shear profile, which
  # the sampler reproduces exactly: the diagnostics log must match its gold and the analytic
  # hub and blade-mean velocities in every row.
  function(add_test_actuator_sampling TEST_NAME TEST_FILES_DIR HUB_U HUB_V)
      gale_setup_test()
      resolve_test_exe("" "erf_exec" TEST_EXE)
      add_test(NAME ${TEST_NAME} COMMAND ${CMAKE_COMMAND}
          "-DMPIEXEC=${MPIEXEC_EXECUTABLE}"
          "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
          "-DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
          "-DNRANKS=${NP}"
          "-DTEST_EXE=${TEST_EXE}"
          "-DCONFIG=$<CONFIG>"
          "-DINPUT=${CURRENT_TEST_BINARY_DIR}/${TEST_FILES_DIR}.i"
          "-DWORKING_DIRECTORY=${CURRENT_TEST_BINARY_DIR}"
          "-DCSV=T1_flow.csv"
          "-DGOLD=${CURRENT_TEST_SOURCE_DIR}/T1_flow.csv.gold"
          "-DSIGDIGITS=10"
          "-DHUB_U=${HUB_U}"
          "-DHUB_V=${HUB_V}"
          "-DERF_TESTS_DIR=${ERF_SOURCE_DIR}/Tests"
          -P ${PROJECT_SOURCE_DIR}/Tests/RunActuatorSampling.cmake)
      set_tests_properties(${TEST_NAME}
          PROPERTIES
          TIMEOUT 600
          PROCESSORS ${NP}
          WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
          LABELS "regression;moving-bodies"
          ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/simulation.log")
  endfunction()
  add_test_actuator_sampling(Actuator_Sampling Actuator_Sampling 12.5 2.5)

  # The same sampling with the domain in one box and split unevenly in x and y (never in z):
  # the sampled velocities must agree to 8 significant digits (the FFT solution itself differs
  # at roundoff between decompositions), so a node on a box face is read through the ghost cells.
  gale_add_test_box_parity(ActuatorSampling_BoxParity Actuator_Sampling "plt00005"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=8 amr.max_grid_size_y=5 amr.max_grid_size_z=64"
      DATALOG "T1_flow.csv"
      DATALOG_SIGDIGITS 8)
endif()

if(ERF_ENABLE_OPENFAST AND ERF_OPENFAST_USE_STUB AND ERF_ENABLE_FFT AND ERF_ENABLE_MPI AND NOT WIN32)
  # A stub OpenFAST turbine as an actuator disk (or, below, an actuator line) in a uniform
  # anelastic flow: its loads are spread as rings about the hub axis (or from the rotating
  # blade nodes) and slow the flow. The gold plotfile and the sampled flow log are the
  # regression; in every row the integrated source must equal minus the turbine's thrust,
  # since the rings (and the line) preserve the rotor force and the spreading is exact.
  function(add_test_openfast_adm TEST_NAME TEST_FILES_DIR PLTFILE)
      # optional 4th argument: the log compared with its gold (default T1_flow.csv); optional
      # 5th: the T1_erf.csv column the integrated source must equal minus (default thrust_x)
      set(_log "T1_flow.csv")
      if(ARGC GREATER 3)
          set(_log "${ARGV3}")
      endif()
      set(_force "thrust_x")
      if(ARGC GREATER 4)
          set(_force "${ARGV4}")
      endif()
      # optional 6th: the file holding that column (default T1_erf.csv; a farm uses
      # moving_bodies/total_load.csv, whose rows the manager writes with the turbine logs)
      set(_turbine_csv "T1_erf.csv")
      if(ARGC GREATER 5)
          set(_turbine_csv "${ARGV5}")
      endif()
      # optional 7th: the columns of the log compared with its gold (default all of them)
      set(_log_columns "")
      if(ARGC GREATER 6)
          set(_log_columns "${ARGV6}")
      endif()
      # optional 8th: the significant digits that log comparison needs (default 10)
      set(_sigdigits 10)
      if(ARGC GREATER 7)
          set(_sigdigits "${ARGV7}")
      endif()
      gale_setup_test()
      resolve_test_exe("" "erf_exec" TEST_EXE)
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
          "-DPLOT_GOLD=${PLOT_GOLD}"
          "-DRTOL=${ERF_TEST_FCOMPARE_RTOL}"
          "-DATOL=${ERF_TEST_FCOMPARE_ATOL}"
          "-DFLOW_CSV=${_log}"
          "-DFLOW_GOLD=${CURRENT_TEST_SOURCE_DIR}/${_log}.gold"
          "-DSIGDIGITS=${_sigdigits}"
          "-DTURBINE_CSV=${_turbine_csv}"
          "-DFORCE_COLUMN=${_force}"
          "-DLOG_COLUMNS=${_log_columns}"
          "-DSOURCE_CSV=moving_bodies/momentum_source.csv"
          "-DERF_TESTS_DIR=${ERF_SOURCE_DIR}/Tests"
          -P ${PROJECT_SOURCE_DIR}/Tests/RunOpenFASTADM.cmake)
      set_tests_properties(${TEST_NAME}
          PROPERTIES
          TIMEOUT 600
          PROCESSORS ${NP}
          WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
          LABELS "regression;moving-bodies"
          ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/simulation.log")
  endfunction()
  add_test_openfast_adm(OpenFAST_ADM_Uniform OpenFAST_ADM_Uniform "plt00010")

  # The driver-only case above, with its turbine log checked too: the rotor speed, thrust, torque
  # and power the stub returns for the prescribed 10 m/s must match the gold log in every row
  # (so the driver stepped the turbine and pulled its loads back), and with mode = none no
  # momentum source may be written. OpenFAST hands its loads back in single precision, so six
  # digits are compared, and the transverse thrust columns, which hold only that noise, are left out.
  add_test_openfast_adm(OpenFAST_DriverOnly OpenFAST_DriverOnly "plt00005"
      "T1_erf.csv" "none" "T1_erf.csv" "time;rotor_speed;thrust_x;torque;power;axis_x;axis_y;axis_z" 6)

  # The same turbine with the domain in one box and split unevenly in x and y: plotfile and
  # sampled flow log must agree, so the rings and their spreading are independent of the
  # decomposition.
  gale_add_test_box_parity(OpenFASTADM_BoxParity OpenFAST_ADM_Uniform "plt00010"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=16 amr.max_grid_size_y=10 amr.max_grid_size_z=64"
      DATALOG "T1_flow.csv"
      DATALOG_SIGDIGITS 8)

  # The same disk with adm_spreading = merged_rings: one ring per radial station for the three blades instead
  # of one per blade node. The stub rotor is rigid, so the blades' rings coincide and the merged ring carries
  # their summed force: the plotfile must match the per-blade rings' to rounding (the sum is taken in another
  # order), and the start-up line must count the 20 rings it built, against 60 for the per-blade rings.
  gale_add_test_option_parity(OpenFAST_ADM_MergedRings OpenFAST_ADM_Uniform "plt00010"
      COMMON_OPTIONS "erf.moving_bodies.T1.fst_file=../stub_turbine.fst"
      ON_OPTIONS "erf.moving_bodies.T1.adm_spreading=merged_rings"
      ON_LOG_REGEX "T1: hub axis .*, 20 rings of 16 points, one per radial station for all the blades"
      OFF_LOG_REGEX "T1: hub axis .*, 60 rings of 16 points"
      FCOMPARE_RTOL "1.0e-12" FCOMPARE_ATOL "1.0e-12")
  set_property(TEST OpenFAST_ADM_MergedRings APPEND PROPERTY LABELS "moving-bodies")

  # The same disk with adm_spreading = line_to_disk: each blade node is spread over the sector between its
  # neighbouring blades with the weight cos^2(N_b dtheta / 4). The stub's three blades carry equal loads in this
  # uniform flow, so the neighbours' weights add to a constant: 16 points per sector are an even ring of
  # 3 * 16 / 2 = 24 azimuths, the disk that rings of 24 points give. The two rings differ by the blades' azimuth
  # only. The kernel's cut-off at three widths and its discrete normalisation leave a small difference in the
  # source for that turn, so the plotfiles agree closely and not to round-off; a weight that did not add to a
  # constant, or to 1, would leave a three-per-revolution pattern or another thrust (measured: 2e-7 relative
  # in u, 5e-6 in v and w; with cos^2(N_b dtheta / 2) 2e-4 and 3e-3). The start-up line must name the
  # 60 sectors. Equal blades do not tell the cos^2 weight from another that adds to a constant; the unit tests
  # (OpenFASTRotor.LineToDisk*) pin the weights, unequal blades and the in-plane force.
  gale_add_test_option_parity(OpenFAST_ADM_LineToDisk OpenFAST_ADM_Uniform "plt00010"
      COMMON_OPTIONS "erf.moving_bodies.T1.fst_file=../stub_turbine.fst"
      OFF_OPTIONS "erf.moving_bodies.T1.num_points_t=24"
      ON_OPTIONS "erf.moving_bodies.T1.adm_spreading=line_to_disk"
      ON_LOG_REGEX "T1: hub axis .*, 60 blade-node sectors of 16 points, from the previous blade to the next"
      OFF_LOG_REGEX "T1: hub axis .*, 60 rings of 24 points"
      FCOMPARE_RTOL "1.0e-5" FCOMPARE_ATOL "1.0e-5")
  set_property(TEST OpenFAST_ADM_LineToDisk APPEND PROPERTY LABELS "moving-bodies")
  # The sectors follow the blades, so their points must be found and spread alike on one box and on boxes split
  # unevenly in x and y.
  gale_add_test_box_parity(OpenFASTADM_LineToDisk_BoxParity OpenFAST_ADM_Uniform "plt00010"
      COMMON_OPTIONS "erf.moving_bodies.T1.adm_spreading=line_to_disk"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=16 amr.max_grid_size_y=10 amr.max_grid_size_z=64"
      DATALOG "T1_flow.csv"
      DATALOG_SIGDIGITS 8)

  # The same disk with sampling = upstream: the node velocities come from one diameter ahead of the
  # hub (the free stream, where OpenFAST's own induction model applies) instead of from the disk.
  # The shifted sampling points must be covered like the nodes, and the rings and spreading are
  # unchanged, so the same three checks and a box-parity twin apply.
  add_test_openfast_adm(OpenFAST_ADM_Upstream OpenFAST_ADM_Upstream "plt00010")
  # The same with a nacelle drag point: its drag needs the velocity at the hub, not one diameter ahead, which
  # the turbine's owner samples as one more point of its exchange. The plotfile and the nacelle column of
  # T1_erf.csv must match the golds of the code that sampled the hub separately on every rank, and the
  # source must equal minus the load with the nacelle's drag.
  add_test_openfast_adm(OpenFAST_ADM_UpstreamNacelle OpenFAST_ADM_UpstreamNacelle "plt00010"
      "T1_erf.csv" "load_x" "T1_erf.csv" "time;nacelle_x;load_x" 8)
  gale_add_test_box_parity(OpenFASTADM_Upstream_BoxParity OpenFAST_ADM_Upstream "plt00010"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=16 amr.max_grid_size_y=10 amr.max_grid_size_z=64"
      DATALOG "T1_flow.csv"
      DATALOG_SIGDIGITS 8)

  # The same deck with sampling = disk_corrected: the velocities are sampled at the disk and the
  # free stream handed to the stub is recovered with the filtered-disk factor and momentum theory
  # on the previous step's thrust (T1_correction.csv). Same three checks, the box-parity twin, and
  # restart parity: the recovered free stream is checkpointed, so the correction log of a run
  # restarted from step 5 must equal the straight run's.
  add_test_openfast_adm(OpenFAST_ADM_DiskCorrected OpenFAST_ADM_DiskCorrected "plt00010")
  gale_add_test_box_parity(OpenFASTADM_DiskCorrected_BoxParity OpenFAST_ADM_DiskCorrected "plt00010"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=16 amr.max_grid_size_y=10 amr.max_grid_size_z=64"
      DATALOG "T1_correction.csv"
      DATALOG_SIGDIGITS 8)
  # The old, unrelaxed update stays selectable (correction_relax = 1): it must reproduce the gold of the
  # code before the relaxation (kept as this test's gold) to 1e-8, the last digits moving only with the
  # order of the sums in the sampler and spreader.
  function(add_test_disk_corrected_old_update)
      set(TEST_NAME OpenFAST_ADM_DiskCorrected_OldUpdate)
      set(TEST_FILES_DIR OpenFAST_ADM_DiskCorrected)
      gale_setup_test()
      resolve_test_exe("" "erf_exec" TEST_EXE)
      add_test(NAME ${TEST_NAME} COMMAND sh -c "${MPI_COMMANDS} ${TEST_EXE} ${CURRENT_TEST_BINARY_DIR}/OpenFAST_ADM_DiskCorrected.i erf.moving_bodies.T1.correction_relax=1 > ${TEST_NAME}.log && ${MPI_FCOMP_COMMANDS} ${FCOMPARE_EXE} --abort_if_not_all_found -a -r 1.0e-8 --abs_tol 1.0e-8 ${PLOT_GOLD} ${CURRENT_TEST_BINARY_DIR}/plt00010")
      set_tests_properties(${TEST_NAME} PROPERTIES TIMEOUT 600 PROCESSORS ${NP}
          WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/" LABELS "regression;moving-bodies"
          ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/${TEST_NAME}.log")
  endfunction()
  add_test_disk_corrected_old_update()
  # With the domain cut into three 20-cell boxes in x (amr.max_grid_size_x = 24) the turbine is owned by rank 1, so the corrected free stream
  # in the checkpoint's state file comes from a rank other than the I/O rank that writes the file.
  gale_add_test_restart_parity(OpenFAST_ADM_DiskCorrected_Restart OpenFAST_ADM_DiskCorrected 5 10
      COMMON_OPTIONS "amr.max_grid_size_x=24"
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      CHK_NRANKS 2 RESTART_NRANKS 2
      DATALOG "T1_correction.csv T1_erf.csv T1_flow.csv T1_stats.csv moving_bodies/momentum_source.csv moving_bodies/total_load.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)

  # The uniform-inflow disk on a terrain-fitted mesh: a 100 m Witch-of-Agnesi ridge with the stub
  # turbine on its top and base_pos z = 0, so the base is raised by the ridge height. The log
  # compared with its gold is moving_bodies/ground.csv (body, x, y, terrain height, base z: the
  # ridge top is a mesh node, so the height is exactly 100); the plotfile gold and fx == -thrust_x
  # exercise the sampler and the spreader on the fitted mesh. Box parity splits the ridge.
  add_test_openfast_adm(OpenFAST_ADM_Terrain OpenFAST_ADM_Terrain "plt00010" "moving_bodies/ground.csv")
  # The ridge case with every column split in z (amr.no_box_split_dir = -1, three boxes up each column, the
  # implicit vertical diffusion off, which ERF requires for that and this deck does not use) on two ranks: the
  # spreading bounds its kernels by each rank's table of node heights; the run must end normally. (A plotfile
  # twin of the unsplit run is not possible: ERF's flow itself differs between the two layouts.)
  add_test_moving_bodies_owners(MovingBodies_Terrain_ColumnsSplitInZ OpenFAST_ADM_Terrain 2
      "amr.no_box_split_dir=-1 amr.max_grid_size_x=16 amr.max_grid_size_y=10 amr.max_grid_size_z=4 erf.implicit_thermal_diffusion=0 erf.implicit_momentum_diffusion=0 max_step=4"
      "STEP 4 ends")
  gale_add_test_box_parity(OpenFASTADM_Terrain_BoxParity OpenFAST_ADM_Terrain "plt00010"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=16 amr.max_grid_size_y=10 amr.max_grid_size_z=64"
      DATALOG "T1_flow.csv"
      DATALOG_SIGDIGITS 8)
  # The ridge case as an actuator line (the limit raised over its 1.11 physical cells per step), with
  # and without erf.moving_bodies.verify_tip_cells: every step checks the cached tip cell heights
  # against the per-region search, and the check changes nothing in the flow (identical plotfiles)
  gale_add_test_option_parity(OpenFAST_ALM_Terrain_VerifyTipCells OpenFAST_ADM_Terrain "plt00010"
      COMMON_OPTIONS "erf.moving_bodies.T1.fst_file=../stub_turbine.fst erf.moving_bodies.T1.mode=alm erf.moving_bodies.T1.fllc=false erf.moving_bodies.alm_max_tip_cells=2"
      ON_OPTIONS "erf.moving_bodies.verify_tip_cells=1")
  set_property(TEST OpenFAST_ALM_Terrain_VerifyTipCells APPEND PROPERTY LABELS "moving-bodies")

  # The same stub turbine as an actuator line (mode = alm): one point per rotating blade node,
  # the tip sweeping 0.9 cells per step under the one-cell limit. Same three checks; the
  # integrated source equals minus the full thrust vector, so fx == -thrust_x holds exactly.
  add_test_openfast_adm(OpenFAST_ALM_Uniform OpenFAST_ALM_Uniform "plt00010")

  # The actuator line in one box and split unevenly in x and y: the blade points fall on
  # different box faces every step, so the plotfile and the flow log must agree.
  gale_add_test_box_parity(OpenFASTALM_BoxParity OpenFAST_ALM_Uniform "plt00010"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=16 amr.max_grid_size_y=10 amr.max_grid_size_z=64"
      DATALOG "T1_flow.csv"
      DATALOG_SIGDIGITS 8)

  # The actuator line with the tower and nacelle forced too: the stub's cylinder drag on 10 tower
  # force nodes and ERF's nacelle drag point at the hub. The integrated source must equal minus
  # the total load (thrust + tower + nacelle: load_x), so the tower and nacelle points are spread
  # exactly; the plotfile carries the tower wake below the rotor.
  add_test_openfast_adm(OpenFAST_ALM_Tower OpenFAST_ALM_Tower "plt00010" "T1_flow.csv" "load_x")

  # The tower and nacelle points sit on the tower axis, which the uneven split puts on a box
  # face: the plotfiles and flow logs must agree with the one-box run.
  gale_add_test_box_parity(OpenFASTALM_Tower_BoxParity OpenFAST_ALM_Tower "plt00010"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=15 amr.max_grid_size_y=12 amr.max_grid_size_z=64"
      DATALOG "T1_flow.csv"
      DATALOG_SIGDIGITS 8)

  # The actuator line, tower and nacelle each spread with their own kernel width (blades 1 cell, tower
  # 2, nacelle 1.5): the plotfile and flow log against their golds, and the source must still integrate
  # to minus the total load (which point gets which width is the gtest OpenFASTRotor.TurbinePoints*).
  add_test_openfast_adm(OpenFAST_ALM_ComponentWidths OpenFAST_ALM_ComponentWidths "plt00010" "T1_flow.csv" "load_x")
  # OpenFAST_ALM_Tower with and without the tower and nacelle widths given equal to epsilon: identical
  # plotfiles, both legs on this machine at zero tolerance (a width not given is epsilon), while that
  # case's own gold holds the shared width to the answers it gave.
  # (each leg runs in its own subdirectory, so the model file is named from there)
  gale_add_test_option_parity(OpenFAST_ALM_Tower_ExplicitWidths OpenFAST_ALM_Tower "plt00010"
      COMMON_OPTIONS "erf.moving_bodies.T1.fst_file=../stub_turbine.fst"
      ON_OPTIONS "erf.moving_bodies.T1.epsilon_tower=2.0 erf.moving_bodies.T1.epsilon_nacelle=2.0")
  set_property(TEST OpenFAST_ALM_Tower_ExplicitWidths APPEND PROPERTY LABELS "moving-bodies")
  # The tower axis on a box face, as for OpenFAST_ALM_Tower: the per-point reach of each kernel must not
  # depend on the decomposition.
  gale_add_test_box_parity(OpenFASTALM_ComponentWidths_BoxParity OpenFAST_ALM_ComponentWidths "plt00010"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=15 amr.max_grid_size_y=12 amr.max_grid_size_z=64"
      DATALOG "T1_flow.csv"
      DATALOG_SIGDIGITS 8)
  # Checkpointed at step 5 and restarted to step 10: the widths come back with the body record, so the
  # restarted run must equal the straight one exactly; a changed tower width must stop the restart.
  gale_add_test_restart_parity(OpenFAST_ALM_ComponentWidths_Restart OpenFAST_ALM_ComponentWidths 5 10
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      DATALOG "T1_fllc.csv T1_erf.csv T1_flow.csv T1_stats.csv moving_bodies/momentum_source.csv moving_bodies/total_load.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)
  gale_add_test_restart_abort(MovingBodies_Restart_ChangedTowerWidth OpenFAST_ALM_ComponentWidths 5
      "T1[.]epsilon_tower changed on restart"
      RESTART_OPTIONS "erf.moving_bodies.T1.epsilon_tower=3.0")

  # The actuator line with the filtered lifting-line correction: the correction log and the
  # plotfile against their golds, and the source still integrates to minus the thrust.
  add_test_openfast_adm(OpenFAST_ALM_FLLC OpenFAST_ALM_FLLC "plt00010" "T1_fllc.csv")

  # The same case checkpointed at step 5 and restarted to step 10: the relaxed correction comes
  # back from the checkpoint, so the plotfile and the correction log must equal the straight
  # run's exactly. With three 20-cell boxes in x (amr.max_grid_size_x = 24) the turbine is owned by rank 1, which writes the correction's
  # and the node loads' checkpoint files and reads them back.
  gale_add_test_restart_parity(OpenFAST_ALM_FLLC_Restart OpenFAST_ALM_FLLC_Restart 5 10
      COMMON_OPTIONS "amr.max_grid_size_x=24"
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      CHK_NRANKS 2 RESTART_NRANKS 2
      DATALOG "T1_fllc.csv T1_erf.csv T1_flow.csv T1_stats.csv moving_bodies/momentum_source.csv moving_bodies/total_load.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)

  # fllc = automatic against the same settings given by hand: fllc = true, epsilon = 0.035 x 2 x 120 m (the
  # stub's rotor_radius) / 10 m (the deck's dx) = 0.84000000000000008 (that product in double precision,
  # written to 17 digits), fllc_eps_chord 0.15, fllc_eps_dr 3, fllc_start_time 5, 300 points: identical
  # plotfiles at zero tolerance. A wrong diameter, radius or level would change epsilon and the plotfile.
  # The correction acts from t = 5 s on.
  # (each leg runs in its own subdirectory, so the model file is named from there)
  gale_add_test_option_parity(OpenFAST_ALM_FLLC_Automatic OpenFAST_ALM_FLLC_Automatic "plt00060"
      COMMON_OPTIONS "erf.moving_bodies.T1.fst_file=../stub_turbine.fst"
      ON_OPTIONS "erf.moving_bodies.T1.fllc=true erf.moving_bodies.T1.epsilon=0.84000000000000008 erf.moving_bodies.T1.fllc_eps_chord=0.15 erf.moving_bodies.T1.fllc_eps_dr=3 erf.moving_bodies.T1.fllc_start_time=5 erf.moving_bodies.T1.num_force_points_blade=300"
      OFF_LOG_REGEX "fllc = automatic: epsilon = 0[.]035 D = 8[.]4 m = 0[.]8400000000000000[0-9]* cells.*D = 2 x 120 m"
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0")
  set_property(TEST OpenFAST_ALM_FLLC_Automatic APPEND PROPERTY LABELS "moving-bodies")
  # Checkpointed at step 55 (after the correction starts) and restarted to step 60 on two ranks, the base in
  # the second of four 32-cell boxes in x: the restart sets the same epsilon from the model and must equal the
  # straight run.
  gale_add_test_restart_parity(OpenFAST_ALM_FLLC_Automatic_Restart OpenFAST_ALM_FLLC_Automatic 55 60
      COMMON_OPTIONS "amr.max_grid_size_x=32"
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      CHK_NRANKS 2 RESTART_NRANKS 2
      DATALOG "T1_fllc.csv T1_erf.csv T1_flow.csv moving_bodies/momentum_source.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)
  # a restart may not switch automatic for the same numbers given by hand
  gale_add_test_restart_abort(MovingBodies_Restart_FllcAutomaticToTrue OpenFAST_ALM_FLLC_Automatic 55
      "T1[.]epsilon changed on restart"
      RESTART_OPTIONS "erf.moving_bodies.T1.fllc=true erf.moving_bodies.T1.epsilon=0.84000000000000008 erf.moving_bodies.T1.fllc_eps_chord=0.15 erf.moving_bodies.T1.fllc_eps_dr=3 erf.moving_bodies.T1.fllc_start_time=5 erf.moving_bodies.T1.num_force_points_blade=300")

  # The disk on two levels: level 1 (25 m) over a box around the rotor is the anchor, sampled and
  # forced with the fine level's step, level 0 carries its force summed onto its faces from level 1.
  # Plotfile and flow-log golds, and the source still integrates to minus the thrust.
  add_test_openfast_adm(OpenFAST_ADM_TwoLevel OpenFAST_ADM_TwoLevel "plt00010")

  # The two-level case in one box per level against the fine level split unevenly on two ranks.
  gale_add_test_box_parity(OpenFASTADM_TwoLevel_BoxParity OpenFAST_ADM_TwoLevel "plt00010"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=16 amr.max_grid_size_y=10 amr.max_grid_size_z=64"
      DATALOG "T1_flow.csv"
      DATALOG_SIGDIGITS 8)

  # The two-level case checkpointed at step 5 and restarted to step 10: the fine level and the
  # turbine on it come back exactly.
  gale_add_test_restart_parity(OpenFAST_ADM_TwoLevel_Restart OpenFAST_ADM_TwoLevel_Restart 5 10
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      DATALOG "T1_flow.csv T1_correction.csv T1_erf.csv T1_stats.csv moving_bodies/momentum_source.csv moving_bodies/total_load.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)

  # The same restart from a checkpoint in the layout of an earlier version: the anchor level's face
  # forces (N) in moving_bodies/force_x, _y, _z instead of its source (N/m^3) in <chk>/StructureCoarseSource.
  # make_legacy_checkpoint.py rewrites the step-5 checkpoint that way (the face volume is
  # (25 m)^3 on level 1); the restart turns the forces back into the source, so level 0's first step
  # after it carries the force and step 10 matches the straight run to rounding. Without the
  # conversion level 0 takes that step unforced and the velocities differ by about 1e-4.
  if(NOT "${ERF_TEST_PYTHON}" STREQUAL "" AND ERF_ENABLE_FCOMPARE)
      set(TEST_NAME OpenFAST_ADM_TwoLevel_RestartLegacy)
      set(TEST_FILES_DIR OpenFAST_ADM_TwoLevel_Restart)
      gale_setup_test()
      unset(TEST_FILES_DIR)
      resolve_test_exe("" "erf_exec" _legacy_exe)
      add_test(NAME ${TEST_NAME}
               COMMAND sh -c "rm -rf plt0* rplt0* chk0* moving_bodies T1_* && ${MPI_COMMANDS} ${_legacy_exe} OpenFAST_ADM_TwoLevel_Restart.i erf.check_int=5 > straight.log 2>&1 && test -f chk00005/StructureCoarseSource/x_faces_H && ${ERF_TEST_PYTHON} make_legacy_checkpoint.py chk00005 force 15625 > legacy.log 2>&1 && ${MPI_COMMANDS} ${_legacy_exe} OpenFAST_ADM_TwoLevel_Restart.i erf.restart=chk00005 erf.plot_file_1=rplt > restart.log 2>&1 && grep -q 'face forces of an earlier version' restart.log && ${MPI_FCOMP_COMMANDS} ${FCOMPARE_EXE} --abort_if_not_all_found --abs_tol 0 --rel_tol 1.0e-10 plt00010 rplt00010"
               WORKING_DIRECTORY ${CURRENT_TEST_BINARY_DIR})
      set_tests_properties(${TEST_NAME} PROPERTIES
          LABELS "regression;moving-bodies" TIMEOUT 600 PROCESSORS ${NP}
          ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/straight.log;${CURRENT_TEST_BINARY_DIR}/legacy.log;${CURRENT_TEST_BINARY_DIR}/restart.log")
  endif()

  # The same restart from a checkpoint of the bodies' own hooks, before they became structure model
  # "gale": the anchor level's source in <chk>/moving_bodies/StructureCoarseSource. The model writes it
  # to <chk>/StructureCoarseSource, where ERF reads it, so the restart matches the straight run exactly.
  # Without the conversion level 0 takes its first step after the restart unforced.
  if(NOT "${ERF_TEST_PYTHON}" STREQUAL "" AND ERF_ENABLE_FCOMPARE)
      set(TEST_NAME OpenFAST_ADM_TwoLevel_RestartBodiesDir)
      set(TEST_FILES_DIR OpenFAST_ADM_TwoLevel_Restart)
      gale_setup_test()
      unset(TEST_FILES_DIR)
      resolve_test_exe("" "erf_exec" _legacy_exe)
      add_test(NAME ${TEST_NAME}
               COMMAND sh -c "rm -rf plt0* rplt0* chk0* moving_bodies T1_* && ${MPI_COMMANDS} ${_legacy_exe} OpenFAST_ADM_TwoLevel_Restart.i erf.check_int=5 > straight.log 2>&1 && test -f chk00005/StructureCoarseSource/x_faces_H && ${ERF_TEST_PYTHON} make_legacy_checkpoint.py chk00005 bodies_dir > legacy.log 2>&1 && ${MPI_COMMANDS} ${_legacy_exe} OpenFAST_ADM_TwoLevel_Restart.i erf.restart=chk00005 erf.plot_file_1=rplt > restart.log 2>&1 && grep -q \"bodies' own directory\" restart.log && test -f chk00005/StructureCoarseSource/x_faces_H && ${MPI_FCOMP_COMMANDS} ${FCOMPARE_EXE} --abort_if_not_all_found --abs_tol 0 --rel_tol 0 plt00010 rplt00010"
               WORKING_DIRECTORY ${CURRENT_TEST_BINARY_DIR})
      set_tests_properties(${TEST_NAME} PROPERTIES
          LABELS "regression;moving-bodies" TIMEOUT 600 PROCESSORS ${NP}
          ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/straight.log;${CURRENT_TEST_BINARY_DIR}/legacy.log;${CURRENT_TEST_BINARY_DIR}/restart.log")
  endif()

  # Two stub turbines as actuator disks, the second two diameters downstream of the first: each
  # runs in its own OpenFAST instance on its owner rank (T1 on rank 0, T2 on rank 1, which owns none,
  # although both bases stand on rank 0's box) and writes its own logs; the integrated source must equal minus the farm's total load,
  # and the downstream turbine's sampled flow log is the gold.
  add_test_openfast_adm(OpenFAST_ADM_TwoTurbines OpenFAST_ADM_TwoTurbines "plt00010" "T2_flow.csv" "load_x" "moving_bodies/total_load.csv")

  # The farm checkpointed at step 5 and restarted to step 10 on two ranks with three 20-cell boxes in x (amr.max_grid_size_x = 24), so
  # turbine T1 is owned (and its logs and checkpoint files written) by rank 1, not the I/O rank that
  # trims the logs, and T2 by rank 0: after a first run that went on past the checkpoint, every
  # turbine's logs must still drop the rows written after it.
  gale_add_test_restart_parity(OpenFAST_ADM_TwoTurbines_Restart OpenFAST_ADM_TwoTurbines 5 10
      COMMON_OPTIONS "amr.max_grid_size_x=24"
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      CHK_NRANKS 2 RESTART_NRANKS 2
      DATALOG "T1_erf.csv T1_flow.csv T1_stats.csv T1_correction.csv T2_erf.csv T2_flow.csv T2_correction.csv moving_bodies/momentum_source.csv moving_bodies/total_load.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)

  # The same farm checkpointed on two ranks (T1 owned by rank 1, T2 by rank 0) and restarted on one,
  # which owns both and reads the files rank 1 wrote: the owners are chosen again from the restart's
  # boxes. The FFT solution differs at roundoff between the rank counts, hence the tolerances.
  gale_add_test_restart_parity(OpenFAST_ADM_TwoTurbines_RestartOnOneRank OpenFAST_ADM_TwoTurbines 5 10
      COMMON_OPTIONS "amr.max_grid_size_x=24"
      CHK_NRANKS 2 RESTART_NRANKS 1
      DATALOG "T1_erf.csv T1_stats.csv T1_correction.csv T2_erf.csv T2_flow.csv T2_correction.csv moving_bodies/total_load.csv"
      DATALOG_SIGDIGITS 8)

  # Which rank owns which turbine, as the tests above rely on, and the rule that gives it: each case's deck run
  # for one step on two ranks must end normally (exit code 0) and print the owners (Tests/RunExpectExit.cmake).
  # With three 20-cell boxes in x (amr.max_grid_size_x = 24) rank 1's box holds the most of T1's footprint; with the default 30-cell boxes both bases
  # stand on rank 0's box, and T2 goes to rank 1, which owns no turbine yet. A second turbine whose OpenFAST
  # model steps with another dt (stub_turbine_dt002.fst) goes to the rank without a turbine; on one rank the
  # two cannot be kept apart and the lockstep check stops the run.
  add_test_moving_bodies_owners(MovingBodies_Owners_TwoTurbines OpenFAST_ADM_TwoTurbines 2 "amr.max_grid_size_x=24"
      "T1: owned by rank 1 .*T2: owned by rank 0 .*STEP 1 ends")
  add_test_moving_bodies_owners(MovingBodies_Owners_FLLC OpenFAST_ALM_FLLC_Restart 2 "amr.max_grid_size_x=24"
      "T1: owned by rank 1 .*STEP 1 ends")
  add_test_moving_bodies_owners(MovingBodies_Owners_DiskCorrected OpenFAST_ADM_DiskCorrected 2 "amr.max_grid_size_x=24"
      "T1: owned by rank 1 .*STEP 1 ends")
  add_test_moving_bodies_owners(MovingBodies_Owners_Balanced OpenFAST_ADM_TwoTurbines 2 ""
      "T1: owned by rank 0 .*T2: owned by rank 1 .*STEP 1 ends")
  # Each distinct model file is read on one rank at start-up (model p on rank p mod nprocs) and its checks
  # handed to every rank. T2's deck names an AeroDyn file with BEM induction and tower shadow on, and is
  # the second model, so rank 1 alone reads it (T2 is also owned by rank 1). With T2's tower forced, the
  # run must warn about the tower shadow and go on: the warning is printed by rank 0, which does not read
  # the file, so it proves the check reached rank 0. With sampling = disk the run must stop on the
  # induction check, naming T2 and the file (that every rank holds the result is the parallel gtest
  # ModelFacts.EveryRankHoldsWhatReadingEachModelGives; here either rank's abort ends the run)
  set(_aerodyn "erf.moving_bodies.T2.fst_file=stub_turbine_aerodyn.fst")
  add_test_moving_bodies_owners(MovingBodies_TowerShadowReadOnRank1 OpenFAST_ADM_TwoTurbines 2
      "${_aerodyn} erf.moving_bodies.T2.num_force_points_tower=10"
      "WARNING: erf[.]moving_bodies[.]T2: the AeroDyn file 'aerodyn_bem_shadow[.]dat' sets TwrShadow = 1.*T2: owned by rank 1 .*STEP 1 ends")
  add_test_moving_bodies_owners(MovingBodies_InductionReadOnRank1 OpenFAST_ADM_TwoTurbines 2
      "${_aerodyn} erf.moving_bodies.T2.sampling=disk"
      "erf[.]moving_bodies[.]T2: the AeroDyn file 'aerodyn_bem_shadow[.]dat' sets Wake_Mod = 1; set it to 0"
      nonzero)
  # The timing summary (erf.moving_bodies.timing_int = 2) on two ranks, one turbine on each: every second step
  # it must print each phase's minimum, mean and maximum over both ranks, the start-up in the first summary
  # only (the second's first row is advance: the timers start again after each summary), and the OpenFAST
  # step of the fastest and slowest of the two turbines (recorded: not zero), and the run must end normally
  add_test_moving_bodies_owners(MovingBodies_TimingSummary OpenFAST_ADM_TwoTurbines 2 "max_step=4 erf.moving_bodies.timing_int=2"
      "steps 1 to 2 [(]2 steps[)]: wall-clock seconds, min / mean / max over 2 ranks.*  startup .*  advance .*  openfast .*  spread .*OpenFAST step per turbine [(]2 turbines[)]: min [1-9][.][0-9]+e-[0-9]+ [(]T[12][)], mean [0-9.e+-]+, max [0-9.e+-]+ [(]T[12][)].*steps 3 to 4 [(]2 steps[)]: wall-clock seconds, min / mean / max over 2 ranks.  advance .*OpenFAST step per turbine [(]2 turbines[)]: min [1-9][.][0-9]+e-[0-9]+ .*STEP 4 ends")
  # three turbines (dt 0.01, 0.02, 0.01) on two ranks: balance alone would put the third on rank 1 with the
  # second; the time steps keep it on rank 0 with the first
  add_test_moving_bodies_owners(MovingBodies_MixedTimeSteps_TwoRanks OpenFAST_ADM_TwoTurbines 2
      "erf.moving_bodies.T2.fst_file=stub_turbine_dt002.fst \"erf.moving_bodies.bodies=T1 T2 T3\" erf.moving_bodies.T3.type=openfast_turbine erf.moving_bodies.T3.mode=adm erf.moving_bodies.T3.fst_file=stub_turbine.fst \"erf.moving_bodies.T3.base_pos=1710. 600. 0.\" erf.moving_bodies.T3.num_force_points_blade=20 erf.moving_bodies.T3.num_points_t=16 erf.moving_bodies.T3.epsilon=2.0 erf.moving_bodies.T3.output_root=T3"
      "T2: owned by rank 1 [(]footprint radius 120 m, OpenFAST dt 0[.]02 s[)].*T3: owned by rank 0 [(]footprint radius 120 m, OpenFAST dt 0[.]01 s[)].*STEP 1 ends")
  # the box-parity split layout of the farm (MovingBodies_Owners_* guard the restart layouts above)
  add_test_moving_bodies_owners(MovingBodies_Owners_BoxParity OpenFAST_ADM_TwoTurbines 2
      "amr.max_grid_size_x=24 amr.max_grid_size_y=12 amr.max_grid_size_z=64"
      "T1: owned by rank 0 .*T2: owned by rank 1 .*STEP 1 ends")
  # the wake lines go with their rotor: with three 20-cell boxes in x, T1's owner, rank 1, samples them, and the
  # lines, 2 and 4 diameters downstream, lie on rank 0's boxes alone (the layout of OpenFAST_ADM_Restart_WakeOwnerRank1 below)
  add_test_moving_bodies_owners(MovingBodies_Owners_Wake OpenFAST_ADM_Restart 2 "amr.max_grid_size_x=24"
      "T1: owned by rank 1 .*T1 wake lines: owner rank 1 exchanges its points with 1 of 2 ranks [(]0[)].*STEP 1 ends")

  # The farm on one rank (both turbines owned by rank 0, one box) against two ranks with the
  # domain cut into three 20-cell boxes in x (amr.max_grid_size_x = 24) (T1 owned by rank 0, T2 by rank 1): the ownership must not change
  # the answer, nor the logs, statistics and correction T2's owner writes, nor the farm's totals,
  # which the I/O rank gathers from both owners.
  gale_add_test_box_parity(OpenFASTADM_TwoTurbines_BoxParity OpenFAST_ADM_TwoTurbines "plt00010"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=24 amr.max_grid_size_y=12 amr.max_grid_size_z=64"
      DATALOG "T2_flow.csv T2_erf.csv T2_stats.csv T2_correction.csv moving_bodies/total_load.csv"
      DATALOG_SIGDIGITS 8)

  # The farm with a kernel width per turbine (T1 2 cells, T2 1 cell): T2's flow log against its gold,
  # the source against minus the farm's total load, and the one-box against the split run (three 20-cell
  # boxes in x: one turbine per rank).
  add_test_openfast_adm(OpenFAST_ADM_TwoWidths OpenFAST_ADM_TwoWidths "plt00010" "T2_flow.csv" "load_x" "moving_bodies/total_load.csv")
  # A turbine and a prescribed-Ct disk behind it, each with its own width: the disk's log against its
  # gold and the source against minus the total load of both.
  add_test_openfast_adm(OpenFAST_ADM_DiskAndTurbine OpenFAST_ADM_DiskAndTurbine "plt00010" "D2_disk.csv" "load_x" "moving_bodies/total_load.csv")
  # The disk and the turbine swapped (the disk upstream) and the domain cut into three 20-cell boxes in x, so the
  # disk is owned by rank 1 and the turbine by rank 0: the I/O rank's total_load.csv must gather the disk's thrust
  # from rank 1, and every file must agree with the one-box run, where rank 0 owns both (the source's y and z
  # totals are roundoff, so values below 1e-5 count as zero).
  set(_disk_upstream "\"erf.moving_bodies.T1.base_pos=1230. 600. 0.\" \"erf.moving_bodies.D2.base_pos=750. 600. 0.\"")
  add_test_moving_bodies_owners(MovingBodies_Owners_DiskAndTurbine OpenFAST_ADM_DiskAndTurbine 2 "amr.max_grid_size_x=24 ${_disk_upstream}"
      "T1: owned by rank 0 .*D2: owned by rank 1 .*STEP 1 ends")
  gale_add_test_box_parity(OpenFASTADM_DiskAndTurbine_OwnerParity OpenFAST_ADM_DiskAndTurbine "plt00010"
      COMMON_OPTIONS "${_disk_upstream}"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=24"
      DATALOG "D2_disk.csv D2_stats.csv T1_erf.csv moving_bodies/total_load.csv moving_bodies/momentum_source.csv"
      DATALOG_SIGDIGITS 8 DATALOG_ZERO_EXPONENT "-5")
  gale_add_test_box_parity(OpenFASTADM_TwoWidths_BoxParity OpenFAST_ADM_TwoWidths "plt00010"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=24 amr.max_grid_size_y=12 amr.max_grid_size_z=64"
      DATALOG "T2_flow.csv"
      DATALOG_SIGDIGITS 8)

  # The farm's logs in one file per rank and in one farm file (erf.moving_bodies.diagnostics_format):
  # with three 20-cell boxes in x T1 is owned by rank 1, T2 by rank 0, so the farm file gathers rows from
  # a rank other than the I/O rank. Each body's rows, split out by the body column, must equal the
  # per_turbine files the goldfile tests check, and the farm's totals must not change.
  set(_farm_logs "T1/erf T1/flow T1/correction T1/stats T2/erf T2/flow T2/correction T2/stats")
  add_test_diagnostics_format(MovingBodies_DiagnosticsFormat_Farm OpenFAST_ADM_TwoTurbines farm
      COMMON_OPTIONS "amr.max_grid_size_x=24" LOGS "${_farm_logs}"
      EXTRA_LOGS "moving_bodies/total_load.csv moving_bodies/momentum_source.csv")
  add_test_diagnostics_format(MovingBodies_DiagnosticsFormat_PerRank OpenFAST_ADM_TwoTurbines per_rank
      COMMON_OPTIONS "amr.max_grid_size_x=24" LOGS "${_farm_logs}"
      EXTRA_LOGS "moving_bodies/total_load.csv")
  # a disk (owned by rank 1) and a turbine (rank 0): the disk's log and statistics through the farm file
  add_test_diagnostics_format(MovingBodies_DiagnosticsFormat_FarmDisk OpenFAST_ADM_DiskAndTurbine farm
      COMMON_OPTIONS "amr.max_grid_size_x=24 ${_disk_upstream}" LOGS "T1/erf T1/flow D2/disk D2/stats"
      EXTRA_LOGS "moving_bodies/total_load.csv moving_bodies/momentum_source.csv")
  # The persistent farm and rank files across a restart: the first run goes on past the checkpoint at
  # step 5, so the restart must trim the rows after it and append to the files (not start them afresh),
  # and every row must equal the straight run's.
  gale_add_test_restart_parity(MovingBodies_DiagnosticsFormat_Farm_Restart OpenFAST_ADM_TwoTurbines 5 10
      COMMON_OPTIONS "amr.max_grid_size_x=24 erf.moving_bodies.diagnostics_format=farm"
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      CHK_NRANKS 2 RESTART_NRANKS 2
      DATALOG "moving_bodies/farm_erf.csv moving_bodies/farm_flow.csv moving_bodies/farm_correction.csv moving_bodies/total_load.csv moving_bodies/momentum_source.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)
  # the same with one file per rank: each rank trims and appends to its own files
  gale_add_test_restart_parity(MovingBodies_DiagnosticsFormat_PerRank_Restart OpenFAST_ADM_TwoTurbines 5 10
      COMMON_OPTIONS "amr.max_grid_size_x=24 erf.moving_bodies.diagnostics_format=per_rank"
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      CHK_NRANKS 2 RESTART_NRANKS 2
      DATALOG "moving_bodies/rank00000_erf.csv moving_bodies/rank00001_erf.csv moving_bodies/rank00000_flow.csv moving_bodies/rank00001_correction.csv moving_bodies/total_load.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)
  # a restart on fewer ranks: the first run (2 ranks) goes on to step 10, the restart (1 rank, no step left)
  # must cut rank 1's files too, though no rank of this run writes them, back to a straight 5-step run's
  # (Tests/RunTrimOnRestart.cmake)
  add_test_trim_on_restart(MovingBodies_DiagnosticsFormat_PerRank_RestartOnOneRank OpenFAST_ADM_TwoTurbines 5 10 2 1
      COMMON_OPTIONS "amr.max_grid_size_x=24 erf.moving_bodies.diagnostics_format=per_rank"
      FILES "moving_bodies/rank00001_erf.csv moving_bodies/rank00001_flow.csv moving_bodies/rank00001_correction.csv moving_bodies/rank00000_erf.csv moving_bodies/total_load.csv"
      TRIMMED_BY "moving_bodies/rank00001_erf.csv:0 moving_bodies/rank00000_erf.csv:0")
  # each owner cuts its own body's files on two ranks: T1 is owned by rank 1, T2 by rank 0, and the I/O rank cuts the totals
  add_test_trim_on_restart(MovingBodies_Restart_OwnersCutTheirLogs OpenFAST_ADM_TwoTurbines 5 10 2 2
      COMMON_OPTIONS "amr.max_grid_size_x=24"
      FILES "T1_erf.csv T1_flow.csv T1_correction.csv T2_erf.csv T2_flow.csv T2_correction.csv moving_bodies/total_load.csv moving_bodies/momentum_source.csv"
      TRIMMED_BY "T1_erf.csv:1 T1_correction.csv:1 T2_erf.csv:0 T2_correction.csv:0 moving_bodies/total_load.csv:0 moving_bodies/momentum_source.csv:0")
  # the same for the wake file: the turbine and its wake lines owned by rank 1
  add_test_trim_on_restart(MovingBodies_Restart_WakeOwnerCutsItsLog OpenFAST_ADM_Restart 5 10 2 2
      COMMON_OPTIONS "amr.max_grid_size_x=24"
      FILES "T1_erf.csv T1_wake.csv"
      TRIMMED_BY "T1_erf.csv:1 T1_wake.csv:1")

  # The logs written with one file open at a time (erf.moving_bodies.max_open_logs = 1): on one rank,
  # which owns both turbines and writes the farm's totals, every row closes another file and opens its
  # own again to append. Every file must hold the bytes of the run with no limit.
  set(_two_logs "T1_erf.csv T1_flow.csv T1_correction.csv T1_stats.csv T2_erf.csv T2_flow.csv T2_correction.csv T2_stats.csv")
  add_test_same_logs(MovingBodies_Logs_OneOpenFile OpenFAST_ADM_TwoTurbines 1
      OPTIONS_A "erf.moving_bodies.diagnostics_format=per_turbine" OPTIONS_B "erf.moving_bodies.max_open_logs=1"
      EXPECT_B "at most 1 diagnostics file"
      FILES "${_two_logs} moving_bodies/total_load.csv moving_bodies/momentum_source.csv")
  # the same through the farm and rank files, two ranks
  add_test_same_logs(MovingBodies_Logs_OneOpenFile_PerRank OpenFAST_ADM_TwoTurbines 2
      COMMON_OPTIONS "amr.max_grid_size_x=24 erf.moving_bodies.diagnostics_format=per_rank"
      OPTIONS_A "erf.moving_bodies.max_open_logs=0" OPTIONS_B "erf.moving_bodies.max_open_logs=1"
      EXPECT_B "at most 1 diagnostics file"
      FILES "moving_bodies/rank00000_erf.csv moving_bodies/rank00001_erf.csv moving_bodies/rank00000_flow.csv moving_bodies/rank00001_flow.csv moving_bodies/rank00000_stats.csv moving_bodies/rank00001_stats.csv moving_bodies/total_load.csv")
  # The statistics rewritten every 4 steps (erf.moving_bodies.stats_int) in a 10-step run without
  # checkpoints: the last rewrite is the one at the end of the run, which must leave the files of the run
  # that rewrites them at every step.
  add_test_same_logs(MovingBodies_StatsInt_EndOfRun OpenFAST_ADM_TwoTurbines 2
      COMMON_OPTIONS "amr.max_grid_size_x=24"
      OPTIONS_A "erf.moving_bodies.stats_int=0" OPTIONS_B "erf.moving_bodies.stats_int=4"
      FILES "${_two_logs}")
  add_test_same_logs(MovingBodies_StatsInt_EndOfRun_Farm OpenFAST_ADM_TwoTurbines 2
      COMMON_OPTIONS "amr.max_grid_size_x=24 erf.moving_bodies.diagnostics_format=farm"
      OPTIONS_A "erf.moving_bodies.stats_int=0" OPTIONS_B "erf.moving_bodies.stats_int=4"
      FILES "moving_bodies/farm_stats.csv moving_bodies/farm_erf.csv")
  # the summary files across a restart: rewritten at the checkpoint at step 5 (the first leg goes on past
  # it), every 3 steps and at the end, with one log open at a time; the restarted run must leave the
  # straight run's statistics and logs
  gale_add_test_restart_parity(MovingBodies_StatsInt_OneOpenFile_Restart OpenFAST_ADM_TwoTurbines 5 10
      COMMON_OPTIONS "amr.max_grid_size_x=24 erf.moving_bodies.stats_int=3 erf.moving_bodies.max_open_logs=1"
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      CHK_NRANKS 2 RESTART_NRANKS 2
      DATALOG "T1_erf.csv T1_flow.csv T1_correction.csv T1_stats.csv T2_erf.csv T2_stats.csv moving_bodies/total_load.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)
  # a restart with no step left, after a first run that went on to step 10: the statistics files must
  # be rewritten from the checkpoint's state, not left as the first run wrote them at step 10
  gale_add_test_restart_parity(MovingBodies_StatsInt_RestartAtTheEnd OpenFAST_ADM_TwoTurbines 5 5
      COMMON_OPTIONS "amr.max_grid_size_x=24 erf.moving_bodies.stats_int=3"
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      CHK_NRANKS 2 RESTART_NRANKS 2 CHK_LEG_END 10
      DATALOG "T1_stats.csv T2_stats.csv"
      DATALOG_SIGDIGITS 10)

  # The same case with wake lines 2, 4 and 7 D behind the rotor, sampled every two steps and
  # averaged from 2 s: the running average must match its gold (the sampler is exact on the
  # faces' trilinear field) and the plotfile its gold.
  add_test_openfast_adm(OpenFAST_ADM_Wake OpenFAST_ADM_Wake "plt00010" "T1_wake_avg.csv")
  # the wake averages and statistics rewritten every 4 steps (stats_int) in this 10-step run, the last at
  # its end: the same files as rewriting them at every sample
  add_test_same_logs(MovingBodies_StatsInt_Wake OpenFAST_ADM_Wake 1
      OPTIONS_A "erf.moving_bodies.stats_int=0" OPTIONS_B "erf.moving_bodies.stats_int=4"
      FILES "T1_wake_avg.csv T1_wake.csv T1_stats.csv T1_erf.csv")

  # The wake lines sampled with the domain in one box and split unevenly: the instantaneous
  # wake file must agree, so a line point on a box face reads the same through the ghost cells.
  # The lateral velocity on the centreline of this symmetric flow is roundoff, so values
  # below 1e-5 m/s count as zero.
  gale_add_test_box_parity(OpenFASTADM_Wake_BoxParity OpenFAST_ADM_Wake "plt00010"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=16 amr.max_grid_size_y=10 amr.max_grid_size_z=64"
      DATALOG "T1_wake.csv"
      DATALOG_SIGDIGITS 8
      DATALOG_ZERO_EXPONENT -5)

  # Turbulent inflow: a periodic Smagorinsky precursor writes its boundary planes, then the
  # stub rotor as a disk runs in the same box with inflow from those planes and outflow, the
  # anelastic FFT solve handling the non-periodic direction. The plotfile, the turbine's
  # running statistics and the integrated-source identity are the regression.
  function(add_test_precursor_inflow TEST_NAME TEST_FILES_DIR PLTFILE)
      gale_setup_test()
      resolve_test_exe("" "erf_exec" TEST_EXE)
      add_test(NAME ${TEST_NAME} COMMAND ${CMAKE_COMMAND}
          "-DMPIEXEC=${MPIEXEC_EXECUTABLE}"
          "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
          "-DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
          "-DNRANKS=${NP}"
          "-DTEST_EXE=${TEST_EXE}"
          "-DCONFIG=$<CONFIG>"
          "-DPRECURSOR_INPUT=${CURRENT_TEST_BINARY_DIR}/precursor.i"
          "-DINPUT=${CURRENT_TEST_BINARY_DIR}/${TEST_FILES_DIR}.i"
          "-DWORKING_DIRECTORY=${CURRENT_TEST_BINARY_DIR}"
          "-DFCOMPARE=${FCOMPARE_EXE}"
          "-DPLTFILE=${PLTFILE}"
          "-DPLOT_GOLD=${PLOT_GOLD}"
          "-DRTOL=${ERF_TEST_FCOMPARE_RTOL}"
          "-DATOL=${ERF_TEST_FCOMPARE_ATOL}"
          "-DSTATS_CSV=T1_stats.csv"
          "-DSTATS_GOLD=${CURRENT_TEST_SOURCE_DIR}/T1_stats.csv.gold"
          "-DSIGDIGITS=10"
          "-DTURBINE_CSV=T1_erf.csv"
          "-DSOURCE_CSV=moving_bodies/momentum_source.csv"
          "-DBNDRY_DIR=BndryFiles"
          "-DERF_TESTS_DIR=${ERF_SOURCE_DIR}/Tests"
          -P ${PROJECT_SOURCE_DIR}/Tests/RunPrecursorInflow.cmake)
      set_tests_properties(${TEST_NAME}
          PROPERTIES
          TIMEOUT 900
          PROCESSORS ${NP}
          WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
          LABELS "regression;moving-bodies"
          ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/precursor.log;${CURRENT_TEST_BINARY_DIR}/simulation.log")
  endfunction()
  add_test_precursor_inflow(OpenFAST_ADM_LES OpenFAST_ADM_LES "plt00010")

  # The same rotor with the turbulent inflow made by the cell perturbation method instead of
  # a precursor: one run, a steady inflow profile with perturbation boxes behind it.
  add_test_openfast_adm(OpenFAST_ADM_CPM OpenFAST_ADM_CPM "plt00010" "T1_stats.csv")

  # The same case checkpointed at step 5 and restarted to step 10: the turbine comes back
  # from its OpenFAST checkpoint, the momentum source is rebuilt from the restored loads and
  # the wake running average continues from its checkpointed sums, so the plotfile and the
  # wake average must equal the straight run's exactly.
  gale_add_test_restart_parity(OpenFAST_ADM_Restart OpenFAST_ADM_Restart 5 10
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      DATALOG "T1_wake_avg.csv T1_wake.csv T1_correction.csv T1_erf.csv T1_flow.csv T1_stats.csv moving_bodies/momentum_source.csv moving_bodies/total_load.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)
  # The same restart with adm_spreading = line_to_disk: the sectors are rebuilt from the blade positions OpenFAST
  # restarts with, and the choice is in the restart record, so the restarted run must match the straight one.
  gale_add_test_restart_parity(OpenFAST_ADM_LineToDisk_Restart OpenFAST_ADM_Restart 5 10
      COMMON_OPTIONS "erf.moving_bodies.T1.adm_spreading=line_to_disk"
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      DATALOG "T1_erf.csv T1_flow.csv moving_bodies/momentum_source.csv moving_bodies/total_load.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)
  # The same restart on two ranks with three 20-cell boxes in x, so that the turbine and its wake lines are owned by
  # rank 1 (MovingBodies_Owners_Wake): rank 1 alone samples the lines, so it must write their files and the running
  # sums into the checkpoint, which the restart takes over.
  gale_add_test_restart_parity(OpenFAST_ADM_Restart_WakeOwnerRank1 OpenFAST_ADM_Restart 5 10
      COMMON_OPTIONS "amr.max_grid_size_x=24"
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      CHK_NRANKS 2 RESTART_NRANKS 2
      DATALOG "T1_wake_avg.csv T1_wake.csv T1_stats.csv moving_bodies/total_load.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)

  # The statistics restored on rank 1 alone (rank 0 owns no body), rewritten through the farm file at the end
  # of a restart with no step left: every rank must agree that they are to be rewritten, as the farm format's
  # rewrite is collective, and the farm file must hold the straight 5-step run's bytes (Tests/RunTrimOnRestart.cmake)
  add_test_trim_on_restart(MovingBodies_StatsInt_Farm_RestartAtTheEnd_OwnerRank1 OpenFAST_ADM_Restart 5 10 2 2
      COMMON_OPTIONS "amr.max_grid_size_x=24 erf.moving_bodies.diagnostics_format=farm erf.moving_bodies.stats_int=3"
      FILES "moving_bodies/farm_stats.csv")
  # A malformed statistics or wake-average file of a turbine owned by rank 1 (three 20-cell boxes in x): its
  # owner alone reads it, and every rank must stop with the owner's message (a rank that skipped the
  # reduction would hang until the timeout). The message must follow the owner line, so the layout is the one meant.
  gale_add_test_restart_abort(MovingBodies_Restart_MalformedStatsOnRank1 OpenFAST_ADM_Restart 5
      "T1: owned by rank 1 .*malformed statistics checkpoint '[^']*T1_stats.dat': the count must be >= 0"
      COMMON_OPTIONS "amr.max_grid_size_x=24" CHK_NRANKS 2 RESTART_NRANKS 2 RUN_TIMEOUT 180
      CORRUPT_FILE "moving_bodies/T1_stats.dat" CORRUPT_TEXT "count = -3|size = 9|t_first = 0|t_last = 1")
  gale_add_test_restart_abort(MovingBodies_Restart_MalformedWakeOnRank1 OpenFAST_ADM_Restart 5
      "T1: owned by rank 1 .*the wake-average checkpoint '[^']*T1_wake_avg.dat' holds 7 values but the lines of T1"
      COMMON_OPTIONS "amr.max_grid_size_x=24" CHK_NRANKS 2 RESTART_NRANKS 2 RUN_TIMEOUT 180
      CORRUPT_FILE "moving_bodies/T1_wake_avg.dat" CORRUPT_TEXT "count = 1|size = 7|hub = 0 0 100|axis = 1 0 0|diameter = 100")

  # A restart continues the same bodies with the same inputs, step and OpenFAST stop time: each
  # change below must stop the restart with a message naming it, before OpenFAST is restarted.
  gale_add_test_restart_abort(MovingBodies_Restart_ChangedBodyKey OpenFAST_ADM_Restart 5
      "T1[.]num_points_t changed on restart"
      RESTART_OPTIONS "erf.moving_bodies.T1.num_points_t=24")
  gale_add_test_restart_abort(MovingBodies_Restart_ChangedAdmSpreading OpenFAST_ADM_Restart 5
      "T1[.]adm_spreading changed on restart [(]rings in the "
      RESTART_OPTIONS "erf.moving_bodies.T1.adm_spreading=merged_rings")
  gale_add_test_restart_abort(MovingBodies_Restart_ChangedToLineToDisk OpenFAST_ADM_Restart 5
      "T1[.]adm_spreading changed on restart [(]rings in the checkpoint, line_to_disk now[)]"
      RESTART_OPTIONS "erf.moving_bodies.T1.adm_spreading=line_to_disk")
  gale_add_test_restart_abort(MovingBodies_Restart_ChangedStep OpenFAST_ADM_Restart 5
      "the checkpoint's bodies stepped 0[.]5"
      RESTART_OPTIONS "erf.fixed_dt=0.25 max_step=20")
  gale_add_test_restart_abort(MovingBodies_Restart_LaterStopTime OpenFAST_ADM_Restart 5
      "were started for OpenFAST to stop at t = 5[.]0"
      RESTART_OPTIONS "stop_time=10.0 max_step=20")
  gale_add_test_restart_abort(MovingBodies_Restart_AddedBody OpenFAST_ADM_Restart 5
      "D1 is not in the checkpoint"
      RESTART_OPTIONS "\"erf.moving_bodies.bodies=T1 D1\" erf.moving_bodies.D1.type=ct_disk \"erf.moving_bodies.D1.base_pos=1500. 600. 0.\" erf.moving_bodies.D1.rotor_radius=120. erf.moving_bodies.D1.hub_height=150. erf.moving_bodies.D1.ct=0.75 erf.moving_bodies.D1.epsilon=2.0 erf.moving_bodies.D1.air_density=1.0 erf.moving_bodies.D1.output_root=D1")
endif()

if(ERF_ENABLE_MOVING_BODIES AND ERF_ENABLE_FFT AND ERF_ENABLE_MPI AND NOT WIN32)
  # A prescribed uniform-Ct disk in a uniform anelastic flow: its force is spread onto the
  # momentum sources and slows the flow. The gold plotfile and the disk's log are the
  # regression; in every row the integrated source must equal the disk's thrust, the exact
  # normalisation of the spreading.
  function(add_test_ct_disk TEST_NAME TEST_FILES_DIR PLTFILE)
      gale_setup_test()
      resolve_test_exe("" "erf_exec" TEST_EXE)
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
          "-DPLOT_GOLD=${PLOT_GOLD}"
          "-DRTOL=${ERF_TEST_FCOMPARE_RTOL}"
          "-DATOL=${ERF_TEST_FCOMPARE_ATOL}"
          "-DCSV=D1_disk.csv"
          "-DGOLD=${CURRENT_TEST_SOURCE_DIR}/D1_disk.csv.gold"
          "-DSIGDIGITS=10"
          "-DCOL_A=thrust"
          "-DCOL_B=spread_thrust"
          "-DERF_TESTS_DIR=${ERF_SOURCE_DIR}/Tests"
          -P ${PROJECT_SOURCE_DIR}/Tests/RunCtDisk.cmake)
      set_tests_properties(${TEST_NAME}
          PROPERTIES
          TIMEOUT 600
          PROCESSORS ${NP}
          WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
          LABELS "regression;moving-bodies"
          ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/simulation.log")
  endfunction()
  add_test_ct_disk(Actuator_UniformCtDisk Actuator_UniformCtDisk "plt00010")

  # A disk on the fine level of two, its fine box tight around it (0.8 R up and down stream), must
  # induce what the same disk induces on one level: the coarse level carries the disk's force too
  # (summed onto its faces from the fine level), so its pressure feels the disk and the induction
  # reaches beyond the fine box. Without that the two-level disk saw 9.15 instead of 8.48 m/s.
  if(ERF_TEST_PYTHON)
      function(add_test_disk_levels TEST_NAME TEST_FILES_DIR)
          gale_setup_test()
          resolve_test_exe("" "erf_exec" TEST_EXE)
          add_test(NAME ${TEST_NAME} COMMAND ${CMAKE_COMMAND}
              "-DMPIEXEC=${MPIEXEC_EXECUTABLE}"
              "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
              "-DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
              "-DNRANKS=2"
              "-DTEST_EXE=${TEST_EXE}"
              "-DCONFIG=$<CONFIG>"
              "-DPYTHON=${ERF_TEST_PYTHON}"
              "-DWORKING_DIRECTORY=${CURRENT_TEST_BINARY_DIR}"
              "-DINPUT_ONE=${CURRENT_TEST_BINARY_DIR}/Actuator_CtDisk_OneLevel.i"
              "-DINPUT_TWO=${CURRENT_TEST_BINARY_DIR}/Actuator_CtDisk_TwoLevel.i"
              "-DCHECKER=${CURRENT_TEST_BINARY_DIR}/check_levels.py"
              "-DU_FREE=10.0"
              "-DTOL=0.1"
              "-DERF_TESTS_DIR=${ERF_SOURCE_DIR}/Tests"
              -P ${PROJECT_SOURCE_DIR}/Tests/RunDiskLevels.cmake)
          set_tests_properties(${TEST_NAME} PROPERTIES
              TIMEOUT 900 PROCESSORS 2 WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
              LABELS "regression;moving-bodies"
              ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/one/simulation.log;${CURRENT_TEST_BINARY_DIR}/two/simulation.log")
      endfunction()
      add_test_disk_levels(Actuator_CtDisk_TwoLevel Actuator_CtDisk_TwoLevel)
  endif()

  # A disk naming the turbine table NREL_5MW_126 beside a constant-Ct disk: in every row the first must
  # take Ct and the power from the table at its free-stream speed and both must give T = 1/2 rho Ct U |U| A
  # (check_turbine_disk.py reads the table itself); both logs carry the ct and power_curve columns.
  if(ERF_TEST_PYTHON)
      function(add_test_turbine_ct_disk TEST_NAME TEST_FILES_DIR)
          gale_setup_test()
          resolve_test_exe("" "erf_exec" TEST_EXE)
          add_test(NAME ${TEST_NAME} COMMAND ${CMAKE_COMMAND}
              "-DMPIEXEC=${MPIEXEC_EXECUTABLE}"
              "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
              "-DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
              "-DNRANKS=${NP}"
              "-DTEST_EXE=${TEST_EXE}"
              "-DCONFIG=$<CONFIG>"
              "-DPYTHON=${ERF_TEST_PYTHON}"
              "-DINPUT=${CURRENT_TEST_BINARY_DIR}/${TEST_FILES_DIR}.i"
              "-DWORKING_DIRECTORY=${CURRENT_TEST_BINARY_DIR}"
              "-DCHECKER=${CURRENT_TEST_BINARY_DIR}/check_turbine_disk.py"
              "-DTABLE=${PROJECT_SOURCE_DIR}/Turbines/Data/PowerCurves/NREL_5MW_126.txt"
              "-DSOURCE_DIR=${CURRENT_TEST_SOURCE_DIR}"
              "-DSIGDIGITS=10"
              "-DERF_TESTS_DIR=${ERF_SOURCE_DIR}/Tests"
              -P ${PROJECT_SOURCE_DIR}/Tests/RunTurbineCtDisk.cmake)
          set_tests_properties(${TEST_NAME} PROPERTIES
              TIMEOUT 600 PROCESSORS ${NP} WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
              LABELS "regression;moving-bodies"
              ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/simulation.log")
      endfunction()
      add_test_turbine_ct_disk(Actuator_TurbineCtDisk Actuator_TurbineCtDisk)
  else()
      message(WARNING "Actuator_TurbineCtDisk is not registered: check_turbine_disk.py needs a Python 3 interpreter")
  endif()

  # The same disk with the domain in one box and split unevenly in x and y: plotfile and disk
  # log must agree, so the spreading is independent of the decomposition.
  gale_add_test_box_parity(ActuatorCtDisk_BoxParity Actuator_UniformCtDisk "plt00010"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=16 amr.max_grid_size_y=10 amr.max_grid_size_z=64"
      DATALOG "D1_disk.csv"
      DATALOG_SIGDIGITS 8)

  # The disk checkpointed at step 5 and restarted to step 10, after a first run that went on past the
  # checkpoint: the disk and source logs must drop the rows written after it. The restart also asks
  # for a later stop time, which a run without turbines may do (only OpenFAST keeps its stop time).
  gale_add_test_restart_parity(MovingBodies_CtDisk_Restart Actuator_UniformCtDisk 5 10
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      RESTART_OPTIONS "stop_time=10.0"
      DATALOG "D1_disk.csv D1_stats.csv moving_bodies/momentum_source.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)
  # a disk input that changes the thrust (here by 2 %, inside the density check's tolerance) must
  # stop the restart
  gale_add_test_restart_abort(MovingBodies_Restart_ChangedDiskDensity Actuator_UniformCtDisk 5
      "D1[.]air_density changed on restart"
      RESTART_OPTIONS "erf.moving_bodies.D1.air_density=1.02")

  # The disk has an owner rank, which alone samples the flow for it and writes its log, statistics and wake lines.
  # With three 20-cell boxes in x (amr.max_grid_size_x = 24) the disk stands on rank 1's box; its points
  # sampled at the first step reach that rank alone, its kernels reach rank 0's box too, and its wake lines
  # lie on rank 0's boxes alone.
  set(_ct_disk_wake "\"erf.moving_bodies.wake.lines_xD=2 4\" erf.moving_bodies.wake.num_points=21 erf.moving_bodies.wake.int=2 erf.moving_bodies.avg_start=2.0")
  # The coverage of a disk's and its wake lines' points by the bodies' level is checked by the body's owner
  # alone, and one reduction stops every rank with the first failure's message (erf_actuator::first_failure,
  # whose hand-over to every rank is the parallel gtest BodyExchange.TheFirstFailureReachesEveryRank): here D1
  # is owned by rank 1 on a refined level (16-cell boxes) whose box is too narrow in y for the disk's kernels,
  # then wide enough for the disk but not for the wake line 2 D behind it, whose half-width reaches past the
  # box. The message must name the point, as before; a rank that skipped the reduction would leave the other
  # waiting, so a short timeout makes that a failure
  set(_cov_level "amr.max_level=1 amr.ref_ratio=2 amr.n_error_buf=0 erf.refinement_indicators=rotor erf.rotor.max_level=1 amr.max_grid_size=16 \"erf.rotor.in_box_hi=1500. 900. 450.\"")
  add_test_moving_bodies_owners(MovingBodies_DiskCoverageOnOwner Actuator_UniformCtDisk 2
      "${_cov_level} \"erf.rotor.in_box_lo=400. 400. 0.\""
      "D1: owned by rank 1 .*erf[.]moving_bodies[.]D1: point [(]750[.]0+, 568[.]8[0-9]*, 170[.]8[0-9]*[)] m [(]with the kernel reach[)] is not covered by the grids of level 1"
      nonzero)
  add_test_moving_bodies_owners(MovingBodies_WakeCoverageOnOwner Actuator_UniformCtDisk 2
      "${_cov_level} \"erf.rotor.in_box_lo=400. 300. 0.\" erf.moving_bodies.wake.lines_xD=2 erf.moving_bodies.wake.num_points=21"
      "D1: owned by rank 1 .*erf[.]moving_bodies[.]wake: the sampling point [(]1230[.]0+, 240[.]0+, 150[.]0+[)] m of D1 is not covered by the grids of level 1"
      nonzero)
  set_tests_properties(MovingBodies_DiskCoverageOnOwner MovingBodies_WakeCoverageOnOwner PROPERTIES TIMEOUT 180)
  # the same for a turbine (OpenFAST_ADM_TwoLevel, T1 owned by rank 1 with 16-cell boxes), whose points only its
  # owner knows; the deck's stub_turbine.fst is read by the stub library only
  if(ERF_ENABLE_OPENFAST AND ERF_OPENFAST_USE_STUB)
    add_test_moving_bodies_owners(MovingBodies_TurbineCoverageOnOwner OpenFAST_ADM_TwoLevel 2
        "amr.max_grid_size=16 \"erf.rotor.in_box_lo=500. 400. 0.\""
        "T1: owned by rank 1 .*erf[.]moving_bodies[.]T1: node [(]750[.]0+, 574[.]5[0-9]*, 194[.]1[0-9]*[)] m [(]with the kernel reach 175[.]0+ m[)] is not covered by the grids of level 1"
        nonzero)
    set_tests_properties(MovingBodies_TurbineCoverageOnOwner PROPERTIES TIMEOUT 180)
  endif()
  # The terrain under every rotor's wake lines is found in one collective at start-up: each line must still
  # start on the ground under its own centre. On the ridge of OpenFAST_ADM_Terrain two Ct disks stand 1 D
  # apart (D1 at x = 1060 m, owned by rank 0; D2 at 1300 m, on rank 1), so D1's line 1 D behind it is centred
  # on D2's base, whose ground (80 m) ground.csv records and which differs from D1's (45.3 m) and from the
  # ground under D2's own line (Tests/RunWakeGround.cmake, Tests/check_wake_ground.py)
  set(_wg_dir ${CMAKE_CURRENT_BINARY_DIR}/test_files/MovingBodies_WakeLinesOnTheGround)
  file(MAKE_DIRECTORY ${_wg_dir})
  file(COPY ${TEST_SOURCE_ROOT}/OpenFAST_ADM_Terrain/OpenFAST_ADM_Terrain.i DESTINATION ${_wg_dir}/)
  resolve_test_exe("" "erf_exec" TEST_EXE)
  set(_wg_disk "type=ct_disk;rotor_radius=120.;hub_height=150.;ct=0.75;epsilon=2.0;air_density=1.0")
  set(_wg_opts "max_step=1;erf.plot_int_1=-1;erf.check_int=-1;erf.moving_bodies.bodies=D1 D2;erf.moving_bodies.wake.lines_xD=1;erf.moving_bodies.wake.num_points=11")
  foreach(_b D1 D2)
      foreach(_kv ${_wg_disk})
          list(APPEND _wg_opts "erf.moving_bodies.${_b}.${_kv}")
      endforeach()
      list(APPEND _wg_opts "erf.moving_bodies.${_b}.output_root=${_b}")
  endforeach()
  list(APPEND _wg_opts "erf.moving_bodies.D1.base_pos=1060. 600. 0." "erf.moving_bodies.D2.base_pos=1300. 600. 0.")
  string(REPLACE ";" "|" _wg_opts_arg "${_wg_opts}")
  add_test(NAME MovingBodies_WakeLinesOnTheGround
      COMMAND ${CMAKE_COMMAND}
          "-DMPIEXEC=${MPIEXEC_EXECUTABLE}" "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}" "-DNRANKS=2"
          "-DTEST_EXE=${TEST_EXE}" "-DINPUT=${_wg_dir}/OpenFAST_ADM_Terrain.i" "-DOPTIONS=${_wg_opts_arg}"
          "-DPYTHON_EXE=${ERF_TEST_PYTHON}" "-DCHECKER=${PROJECT_SOURCE_DIR}/Tests/check_wake_ground.py"
          "-DCHECKS=D1:D2:1" "-DWORKING_DIRECTORY=${_wg_dir}"
          -P ${PROJECT_SOURCE_DIR}/Tests/RunWakeGround.cmake)
  set_tests_properties(MovingBodies_WakeLinesOnTheGround PROPERTIES
      LABELS "regression;moving-bodies" TIMEOUT 600 PROCESSORS 2 WORKING_DIRECTORY "${_wg_dir}/"
      ATTACHED_FILES_ON_FAIL "${_wg_dir}/simulation.log")
  add_test_moving_bodies_owners(MovingBodies_Owners_CtDisk Actuator_UniformCtDisk 2 "amr.max_grid_size_x=24 ${_ct_disk_wake}"
      "D1: owned by rank 1 [(]footprint radius 120 m[)].*D1: owner rank 1 exchanges its points with 1 of 2 ranks [(]1[)].*D1: owner rank 1 exchanges its points with 2 of 2 ranks [(]0 1[)].*D1 wake lines: owner rank 1 exchanges its points with 1 of 2 ranks [(]0[)].*STEP 1 ends")
  # The disk with wake lines in one box (owned by rank 0, the I/O rank) and in three 20-cell boxes in x (owned
  # by rank 1): the answer and every file the owner writes must agree (the logs to 8 digits, as the FFT solution
  # differs at roundoff between the two layouts).
  gale_add_test_box_parity(ActuatorCtDisk_OwnerParity Actuator_UniformCtDisk "plt00010"
      COMMON_OPTIONS "${_ct_disk_wake}"
      REFERENCE_OPTIONS "amr.max_grid_size=1024"
      SPLIT_OPTIONS "amr.max_grid_size_x=24"
      DATALOG "D1_disk.csv D1_stats.csv D1_wake.csv D1_wake_avg.csv moving_bodies/momentum_source.csv"
      DATALOG_SIGDIGITS 8)
  # The disk owned by rank 1 checkpointed at step 5 and restarted to step 10 on two ranks, after a first run that
  # went on past the checkpoint: the I/O rank trims the logs rank 1 writes, and the restart takes over the statistics
  # and wake sums rank 1 wrote into the checkpoint. The lines are sampled every step and averaged from 1 s, so the
  # checkpoint holds three wake samples (and two of the statistics).
  set(_ct_disk_wake_restart "amr.max_grid_size_x=24 \"erf.moving_bodies.wake.lines_xD=2 4\" erf.moving_bodies.wake.num_points=21 erf.moving_bodies.wake.int=1 erf.moving_bodies.avg_start=1.0")
  gale_add_test_restart_parity(MovingBodies_CtDisk_Restart_OwnerRank1 Actuator_UniformCtDisk 5 10
      COMMON_OPTIONS "${_ct_disk_wake_restart}"
      FCOMPARE_RTOL "0.0" FCOMPARE_ATOL "0.0"
      CHK_NRANKS 2 RESTART_NRANKS 2
      DATALOG "D1_disk.csv D1_stats.csv D1_wake.csv D1_wake_avg.csv moving_bodies/momentum_source.csv"
      DATALOG_SIGDIGITS 10 OVERRUN)
  # The same checkpoint restarted on one rank, which then owns the disk and reads the sums rank 1 wrote. The FFT
  # solution differs at roundoff between the rank counts, hence the default plotfile tolerances and 8 digits.
  gale_add_test_restart_parity(MovingBodies_CtDisk_RestartOnOneRank Actuator_UniformCtDisk 5 10
      COMMON_OPTIONS "${_ct_disk_wake_restart}"
      CHK_NRANKS 2 RESTART_NRANKS 1
      DATALOG "D1_disk.csv D1_stats.csv D1_wake.csv D1_wake_avg.csv moving_bodies/momentum_source.csv"
      DATALOG_SIGDIGITS 8 DATALOG_ZERO_EXPONENT "-5" OVERRUN)
endif()
if(ERF_ENABLE_OPENFAST AND NOT ERF_OPENFAST_USE_STUB AND ERF_ENABLE_FFT AND ERF_ENABLE_MPI AND NOT WIN32)
  # The IEA 15 MW reference turbine run by the real OpenFAST library (built with ERF_OPENFAST_USE_STUB=OFF),
  # on the summit of the Askervein hill in a uniform 10 m/s inflow with a pressure outflow 3.3 km downstream:
  # an actuator disk and an actuator line with its tower and nacelle. Each test copies the model
  # (Exec/CanonicalTests/MovingBodies/IEA15_land_model) and the Askervein terrain file next to its deck.
  # The plotfile, the sampled flow log and the turbine's loads, torque and power (T1_erf.csv) are compared
  # with golds at 1e-6 relative and six printed digits, and the golds are per platform: "_macOS" for
  # macOS arm64 (Apple clang, Release, Homebrew gfortran, Accelerate) and "_Linux" for the CI job
  # (GCC 11, Release, OpenFAST 5.0.0 from Build/setup_openfast.sh), both with OpenFAST 5.0.0.
  #
  # One gold set cannot serve both at a useful tolerance. The two platforms agree exactly for the first
  # four steps, then part: the line's filtered lifting-line correction (T1_fllc.csv, du_max 6e-5 relative
  # at step 4) and the disk's correction (T1_correction.csv, from 1e-9 at step 1) feed their own output
  # back, so a last-bit difference in a filter - a different libm and Fortran compiler - grows over the
  # ten steps to 4e-5 relative in the velocities, 1e-3 in the thrust and 4e-3 in the power. Passing one
  # gold set on both would need about 1e-4 on the plotfile and 1e-2 on the power, which is coarser than
  # the changes these cases exist to catch. Within one platform the answers are reproducible: OpenFAST's
  # loads cross to ERF in single precision (rounding is at most 6e-8 relative, of order 1e-8 relative in
  # the flow), and 1-rank and 2-rank runs agree to 1e-15 and to every printed digit. A gold set is
  # refreshed on the platform it belongs to. The load check is an identity and holds on both platforms:
  # minus the total load for the line (8 digits), minus the shaft component of the thrust for the disk
  # (1e-8, Tests/check_openfast_shaft_source.py).
  # Darwin takes the macOS golds; every other system this job runs on (Linux) takes the Linux ones.
  if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
      set(ASKERVEIN_GOLD_PLATFORM "macOS")
  else()
      set(ASKERVEIN_GOLD_PLATFORM "Linux")
  endif()
  function(add_test_openfast_real TEST_NAME LOG FORCE_COLUMN)
      set(TEST_FILES_DIR ${TEST_NAME})
      gale_setup_test()
      # the gold plotfile of this platform (gale_setup_test set PLOT_GOLD to the name without a suffix)
      set(PLOT_GOLD ${PLOT_GOLD}_${ASKERVEIN_GOLD_PLATFORM})
      file(COPY ${TEST_SOURCE_ROOT}/IEA15_land_model DESTINATION ${CURRENT_TEST_BINARY_DIR})
      file(COPY ${ERF_SOURCE_DIR}/Exec/CanonicalTests/Real_Terrain/Askervein/askervein.txt DESTINATION ${CURRENT_TEST_BINARY_DIR})
      resolve_test_exe("" "erf_exec" TEST_EXE)
      add_test(NAME ${TEST_NAME} COMMAND ${CMAKE_COMMAND}
          "-DMPIEXEC=${MPIEXEC_EXECUTABLE}"
          "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
          "-DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
          "-DNRANKS=${NP}"
          "-DTEST_EXE=${TEST_EXE}"
          "-DCONFIG=$<CONFIG>"
          "-DINPUT=${CURRENT_TEST_BINARY_DIR}/${TEST_NAME}.i"
          "-DWORKING_DIRECTORY=${CURRENT_TEST_BINARY_DIR}"
          "-DFCOMPARE=${FCOMPARE_EXE}"
          "-DPLTFILE=plt00010"
          "-DPLOT_GOLD=${PLOT_GOLD}"
          "-DRTOL=1.0e-6"
          "-DATOL=1.0e-6"
          "-DFLOW_CSV=${LOG}"
          "-DFLOW_GOLD=${CURRENT_TEST_SOURCE_DIR}/${LOG}.${ASKERVEIN_GOLD_PLATFORM}.gold"
          "-DSIGDIGITS=6"
          "-DZERO_EXPONENT=-4"
          "-DTURBINE_CSV=T1_erf.csv"
          "-DTURBINE_GOLD=${CURRENT_TEST_SOURCE_DIR}/T1_erf.csv.${ASKERVEIN_GOLD_PLATFORM}.gold"
          "-DTURBINE_COLUMNS=time;rotor_speed;thrust_x;torque;power;tower_x;nacelle_x;load_x"
          "-DFORCE_COLUMN=${FORCE_COLUMN}"
          "-DSOURCE_CSV=moving_bodies/momentum_source.csv"
          "-DPYTHON_EXE=${ERF_TEST_PYTHON}"
          "-DERF_TESTS_DIR=${ERF_SOURCE_DIR}/Tests"
          -P ${PROJECT_SOURCE_DIR}/Tests/RunOpenFASTADM.cmake)
      set_tests_properties(${TEST_NAME}
          PROPERTIES
          TIMEOUT 900
          PROCESSORS ${NP}
          WORKING_DIRECTORY "${CURRENT_TEST_BINARY_DIR}/"
          LABELS "regression;moving-bodies;openfast-real"
          ATTACHED_FILES_ON_FAIL "${CURRENT_TEST_BINARY_DIR}/simulation.log")
  endfunction()
  # the disk's load check runs a Python script
  if(NOT "${ERF_TEST_PYTHON}" STREQUAL "")
      add_test_openfast_real(OpenFAST_ADM_Askervein "T1_flow.csv" "shaft_x")
  else()
      message(WARNING "OpenFAST_ADM_Askervein is not registered: its load check needs a Python 3 interpreter")
  endif()
  add_test_openfast_real(OpenFAST_ALM_Askervein "T1_flow.csv" "load_x")

  # The IEA 15 MW turbine under its ROSCO controller (Exec/CanonicalTests/MovingBodies/OpenFAST_IEA15_PowerCurve)
  # on a flat domain at 9 m/s, for ten steps: the disk on one and two levels, the line on two and three. Registered when the
  # build knows a ROSCO library (ROSCO_DIR or ERF_BUILD_ROSCO). Each test makes its run folder with the case's
  # prepare.py, requires that ServoDyn loaded ROSCO, and compares the turbine's rotor speed, thrust, torque and
  # power with a gold made on macOS arm64 with OpenFAST 5.0.0 and ROSCO 2.10.1, to six digits as for the
  # Askervein tests. The torque is the controller's answer, so a run without the controller fails both checks.
  if(ERF_ROSCO_LIBRARY AND NOT "${ERF_TEST_PYTHON}" STREQUAL "")
      function(add_test_iea15_power_curve DECK)
          set(TEST_NAME OpenFAST_IEA15_PowerCurve_${DECK})
          set(_case_dir ${TEST_SOURCE_ROOT}/OpenFAST_IEA15_PowerCurve)
          set(_bin_dir ${CMAKE_CURRENT_BINARY_DIR}/test_files/${TEST_NAME})
          file(MAKE_DIRECTORY ${_bin_dir})
          resolve_test_exe("" "erf_exec" TEST_EXE)
          add_test(NAME ${TEST_NAME} COMMAND ${CMAKE_COMMAND}
              "-DMPIEXEC=${MPIEXEC_EXECUTABLE}"
              "-DMPIEXEC_NUMPROC_FLAG=${MPIEXEC_NUMPROC_FLAG}"
              "-DMPIEXEC_PREFLAGS=${MPIEXEC_PREFLAGS}"
              "-DNRANKS=2"
              "-DTEST_EXE=${TEST_EXE}"
              "-DCONFIG=$<CONFIG>"
              "-DCASE_DIR=${_case_dir}"
              "-DDECK=${DECK}"
              "-DLIBDISCON=${ERF_ROSCO_LIBRARY}"
              "-DPYTHON_EXE=${ERF_TEST_PYTHON}"
              "-DWORKING_DIRECTORY=${_bin_dir}"
              "-DTURBINE_GOLD=${_case_dir}/gold/${DECK}_T1_erf.csv.gold"
              "-DERF_TESTS_DIR=${ERF_SOURCE_DIR}/Tests"
              -P ${PROJECT_SOURCE_DIR}/Tests/RunIEA15PowerCurve.cmake)
          set_tests_properties(${TEST_NAME}
              PROPERTIES
              TIMEOUT 900
              PROCESSORS 2
              WORKING_DIRECTORY "${_bin_dir}/"
              LABELS "regression;moving-bodies;openfast-real;rosco"
              ATTACHED_FILES_ON_FAIL "${_bin_dir}/simulation.log")
      endfunction()
      add_test_iea15_power_curve(adm_20m)
      add_test_iea15_power_curve(adm_10m)
      add_test_iea15_power_curve(alm_10m)
      add_test_iea15_power_curve(alm_5m)
  elseif(ERF_ROSCO_LIBRARY)
      message(WARNING "The OpenFAST_IEA15_PowerCurve tests are not registered: prepare.py needs a Python 3 interpreter")
  endif()
endif()
if(ERF_ROSCO_LIBRARY AND NOT "${ERF_TEST_PYTHON}" STREQUAL "")
  # The ROSCO controller library found with ROSCO_DIR or built with ERF_BUILD_ROSCO loads and exports
  # DISCON, the entry point OpenFAST's ServoDyn calls (DLL_ProcName). ERF does not link against the
  # library, so this is the build's only check that it is usable. The verdict is the exit code: a
  # missing symbol raises, and Python's traceback repeats the source line, so a pass regex on the
  # printed text would also match the failure.
  add_test(NAME ROSCO_Library
      COMMAND ${ERF_TEST_PYTHON} -c
          "import ctypes, sys; lib = ctypes.CDLL(sys.argv[1]); lib.DISCON; print('DISCON found in', sys.argv[1])"
          ${ERF_ROSCO_LIBRARY})
  set_tests_properties(ROSCO_Library PROPERTIES
      TIMEOUT 60
      LABELS "openfast-real;rosco")
endif()

if(ERF_ENABLE_MOVING_BODIES AND NOT "${ERF_TEST_PYTHON}" STREQUAL "")
  # The shaft-thrust checker of the real-OpenFAST disk case on fixed logs: the real case's own logs must
  # pass; with one row's source off by 1e-6 it must fail; and on a stub disk, whose loads lie along x, it
  # must refuse to count the plain x identity as the shaft check.
  # The verdict is the exit code (the runner acts on it), so each case requires the exit code as well as
  # the message (Tests/RunExpectExit.cmake).
  foreach(_case pass mismatch plain_x)
      if(_case STREQUAL "pass")
          set(_result 0)
          set(_expect "fx equals -[(]T[.]n[)] n_x to")
      elseif(_case STREQUAL "mismatch")
          set(_result 1)
          set(_expect "fx differs from -[(]T[.]n[)] n_x by 1[.]00e-06")
      else()
          set(_result 1)
          set(_expect "the loads lie along x")
      endif()
      set(_dir ${PROJECT_SOURCE_DIR}/Tests/test_files/ShaftSourceChecker/${_case})
      add_test(NAME MovingBodies_ShaftSourceChecker_${_case}
          COMMAND ${CMAKE_COMMAND}
              "-DCHECK_COMMAND=${ERF_TEST_PYTHON};${PROJECT_SOURCE_DIR}/Tests/check_openfast_shaft_source.py;--turbine;${_dir}/T1_erf.csv;--source;${_dir}/moving_bodies/momentum_source.csv"
              "-DEXPECTED_RESULT=${_result}"
              "-DEXPECTED_REGEX=${_expect}"
              -P ${PROJECT_SOURCE_DIR}/Tests/RunExpectExit.cmake)
      set_tests_properties(MovingBodies_ShaftSourceChecker_${_case} PROPERTIES
          LABELS "regression;moving-bodies" TIMEOUT 60)
  endforeach()
endif()
unset(TEST_SOURCE_ROOT)

if(ERF_ENABLE_OPENFAST AND ERF_OPENFAST_USE_STUB AND ERF_ENABLE_FFT AND ERF_ENABLE_MPI AND NOT WIN32)
  # The moving-bodies start-up checks, one deck each: every abort must name the input to change.
  set(_mb_cases ${PROJECT_SOURCE_DIR}/Exec/CanonicalTests/MovingBodies)
  # the actuator core carries no map factors: with one other than 1 (erf.test_mapfactor: 0.5 and 0.25) the run stops
  add_test_abort(MovingBodies_MapFactorsNotOne ${_mb_cases}/Actuator_UniformCtDisk Actuator_UniformCtDisk.i
                 "erf.moving_bodies: the bodies' forces are spread and the velocities sampled without map factors, but level 0 has a map factor other than 1"
                 "erf.test_mapfactor=true")
  add_test_abort(MovingBodies_AnchorLevelAboveFinest ${_mb_cases}/OpenFAST_ADM_Restart OpenFAST_ADM_Restart.i
      "anchor_level = 1 is not a level of this run" "erf.moving_bodies.anchor_level=1")
  add_test_abort(MovingBodies_AdmSpreadingUnknown ${_mb_cases}/OpenFAST_ADM_Restart OpenFAST_ADM_Restart.i
      "T1[.]adm_spreading must be rings, merged_rings or line_to_disk, not 'merged'" "erf.moving_bodies.T1.adm_spreading=merged")
  # two turbines whose OpenFAST models step with different dt on one rank, which steps them together
  add_test_abort(MovingBodies_MixedTimeSteps_OneRank ${_mb_cases}/OpenFAST_ADM_TwoTurbines OpenFAST_ADM_TwoTurbines.i
      "use different time steps [(]25 vs 50 substeps per ERF step[)]" "erf.moving_bodies.T2.fst_file=stub_turbine_dt002.fst")
  # ERF hands the model no heights with EB or ImmersedForcing terrain: the bodies would stand on
  # prob_lo z with their kernels in the terrain; ImmersedForcing must stop the run, naming it
  add_test_abort(MovingBodies_ImmersedForcingTerrainRefused ${_mb_cases}/OpenFAST_ADM_Restart OpenFAST_ADM_Restart.i
      "does not run with erf[.]terrain_type = ImmersedForcing" "erf.terrain_type=ImmersedForcing")
  # erf.init_shrink below 1 shortens ERF's first step: the run must stop at the start, naming the key,
  # not at step 1 with a step-change message
  add_test_abort(MovingBodies_InitShrinkRefused ${_mb_cases}/OpenFAST_ADM_Restart OpenFAST_ADM_Restart.i
      "erf[.]init_shrink = 0[.]5[0-9]* changes ERF's first step" "erf.init_shrink=0.5")
  add_test_abort(MovingBodies_StopTimeNotWholeSteps ${_mb_cases}/OpenFAST_ADM_Restart OpenFAST_ADM_Restart.i
      "steps of erf[.]fixed_dt = 0[.]5.*not a whole" "stop_time=4.75 max_step=-1")
  # on two levels the stop time must be a whole number of level-0 steps, which ERF cuts, not of the
  # bodies' finer steps: 4.75 s is 19 steps of level 1 but 9.5 of level 0
  # fllc = automatic on 50 m cells: 8.4 m is 0.17 cells, below the 0.75 it accepts, and the run must stop
  add_test_abort(MovingBodies_FllcAutomaticCellsTooCoarse ${_mb_cases}/OpenFAST_ALM_FLLC_Automatic OpenFAST_ALM_FLLC_Automatic.i
      "fllc = automatic: epsilon = 0[.]035 D = 8[.]4[0-9]* m is 0[.]168[0-9]* cells.*below 0[.]75" "amr.n_cell=24 12 8 erf.fixed_dt=0.5 max_step=1")
  # fllc = automatic sets epsilon itself: the deck's own epsilon must stop the run, naming it
  add_test_abort(MovingBodies_FllcAutomaticWithEpsilon ${_mb_cases}/OpenFAST_ALM_FLLC OpenFAST_ALM_FLLC.i
      "T1[.]epsilon cannot be given with erf[.]moving_bodies[.]T1[.]fllc = automatic" "erf.moving_bodies.T1.fllc=automatic")
  add_test_abort(MovingBodies_StopTimeNotWholeCoarseSteps ${_mb_cases}/OpenFAST_ADM_TwoLevel OpenFAST_ADM_TwoLevel.i
      "is 9[.]5[0-9]* steps of erf[.]fixed_dt = 0[.]5.*not a whole" "stop_time=4.75 max_step=-1")
  # a stop time that is no whole number of steps is fine when max_step ends the run first, as no step
  # is cut: the run must start (the deck's own MovingBodies tests run to max_step = 1)
  add_test_abort(MovingBodies_MaxStepEndsTheRunFirst ${_mb_cases}/OpenFAST_ADM_Restart OpenFAST_ADM_Restart.i
      "STEP 1 ends" "stop_time=1000000.3")
  # the bodies' level must exist when they are placed: the deck keeps amr.max_level = 1 (so the bodies
  # live on level 1 by default) but erf.rotor.max_level = 0 stops the refinement that would make level 1,
  # so the run starts with level 0 only (amr.max_level = 0 would instead put the bodies on level 0)
  add_test_abort(MovingBodies_AnchorLevelMissingAtStart ${_mb_cases}/OpenFAST_ADM_TwoLevel OpenFAST_ADM_TwoLevel.i
      "the bodies live on level 1" "erf.rotor.max_level=0")
  # a nacelle drag area above 2 pi epsilon_nacelle^2 takes its kernel correction factor under 0.5, where the
  # linear estimate fails: 60 m^2 against 2 pi (0.06 x 50 m)^2 = 56.5 m^2 (factor 0.47); and a width for a
  # component that is off
  add_test_abort(MovingBodies_NacelleKernelTooNarrow ${_mb_cases}/OpenFAST_ALM_ComponentWidths OpenFAST_ALM_ComponentWidths.i
      "nacelle_area = 60 m.2 exceeds 2 pi epsilon_nacelle" "erf.moving_bodies.T1.epsilon_nacelle=0.06")
  add_test_abort(MovingBodies_TowerWidthWithoutTower ${_mb_cases}/OpenFAST_ADM_Restart OpenFAST_ADM_Restart.i
      "T1[.]epsilon_tower is given but erf[.]moving_bodies[.]T1[.]num_force_points_tower is not" "erf.moving_bodies.T1.epsilon_tower=1.0")
  add_test_abort(MovingBodies_CtDiskDensityMismatch ${_mb_cases}/Actuator_UniformCtDisk Actuator_UniformCtDisk.i
      "D1[.]air_density = 1[.]2.*more than erf[.]moving_bodies[.]density_tolerance" "erf.moving_bodies.D1.air_density=1.2")
  add_test_abort(MovingBodies_FinerLevelOverTheBodies ${_mb_cases}/OpenFAST_ADM_TwoLevel OpenFAST_ADM_TwoLevel.i
      "structure model .gale. couples to level 0, but level 1 covers part of its support" "erf.moving_bodies.anchor_level=0")
  # with the bodies above level 0 the coarser levels take their force only with two-way coupling
  add_test_abort(MovingBodies_OneWayAboveLevel0 ${_mb_cases}/OpenFAST_ADM_TwoLevel OpenFAST_ADM_TwoLevel.i
      "the coarser levels take their force only with erf[.]coupling_type = TwoWay" "erf.coupling_type=OneWay")
  add_test_abort(MovingBodies_FPETrapsRefused ${_mb_cases}/OpenFAST_ADM_Restart OpenFAST_ADM_Restart.i
      "OpenFAST is not floating-point-exception clean" "amrex.fpe_trap_invalid=1")
  add_test_abort(MovingBodies_TimingIntNegative ${_mb_cases}/OpenFAST_ADM_Restart OpenFAST_ADM_Restart.i
      "erf[.]moving_bodies[.]timing_int must be >= 0" "erf.moving_bodies.timing_int=-1")
  # without erf.moving_bodies.timing_int the run prints no timing summary in four steps (not an abort: the
  # helper's pass and fail patterns serve a run that must end normally too)
  add_test_abort(MovingBodies_NoTimingByDefault ${_mb_cases}/OpenFAST_ADM_Restart OpenFAST_ADM_Restart.i
      "STEP 4 ends" "max_step=4")
  set_tests_properties(MovingBodies_NoTimingByDefault PROPERTIES FAIL_REGULAR_EXPRESSION "Moving bodies timing")
  add_test_abort(MovingBodies_CorrectionRelaxOutOfRange ${_mb_cases}/OpenFAST_ADM_DiskCorrected OpenFAST_ADM_DiskCorrected.i
      "T1[.]correction_relax must be -1" "erf.moving_bodies.T1.correction_relax=1.5")
  # fllc_relax at or above 4 eps_chord / (2 eps_chord + 1.057) (0.642 at the default eps_chord 0.25) makes
  # the correction grow from one update to the next: the run stops at start-up, naming the bound
  add_test_abort(MovingBodies_FllcRelaxAboveStabilityBound ${_mb_cases}/OpenFAST_ALM_FLLC OpenFAST_ALM_FLLC.i
      "T1[.]fllc_relax = 0[.]65 is at or above the stability bound 0[.]642167" "erf.moving_bodies.T1.fllc_relax=0.65")
  # the actuator-line cases pass the tip-travel limit; this one must not, and must name the step that would
  add_test_abort(MovingBodies_ALMTipTravelLimit ${_mb_cases}/OpenFAST_ALM_Uniform OpenFAST_ALM_Uniform.i
      "the blade tip sweeps 0[.]9[0-9]* cells per step.*use erf[.]fixed_dt <= 0[.]0054" "erf.moving_bodies.alm_max_tip_cells=0.01")
  # the same line over the 100 m ridge (ztop 600 m, dz 50 m): the cells at the crest are 50 * 500 / 600 =
  # 41.67 m tall (41.65 m with the slope of their faces next to the crest), so the tip that sweeps 0.93
  # nominal cells per step sweeps 1.11 physical cells and the run must stop, naming the physical height
  # (with the nominal 50 m it ran)
  add_test_abort(MovingBodies_ALMTipTravelPhysicalCells ${_mb_cases}/OpenFAST_ADM_Terrain OpenFAST_ADM_Terrain.i
      "the blade tip sweeps 1[.]11[0-9]* cells per step.*limiting cell height 41[.]65" "erf.moving_bodies.T1.mode=alm erf.moving_bodies.T1.fllc=false")
  # the same line on a stretched mesh, 8 m cells at the ground growing to 50 m at the hub (150 m): the tip
  # crosses the short cells low in the disk moving mostly sideways, so the 17 m cell at 24-41 m and the 38 m
  # one above it count as 47.63 m, and the limit is the 46.5 m cell just under the hub, 47.60 m; the line
  # sweeps 0.97 cells, under the default limit of one (the 17 m cell alone would give 2.7 and stop the run);
  # the limit lowered to 0.5 makes the run print the count
  add_test_abort(MovingBodies_ALMTipTravelStretched ${_mb_cases}/OpenFAST_ALM_Uniform OpenFAST_ALM_Uniform.i
      "the blade tip sweeps 0[.]97[0-9]* cells per step.*limiting cell height 47[.]59"
      "erf.moving_bodies.alm_max_tip_cells=0.5 'erf.terrain_z_levels=0 7.7 15.7 23.7 40.8 78.5 125 175 225 275 350 450 600'")
  # the line over the ridge with the cached tip cell heights checked against the per-region search: the
  # check passes and the run stops as above, with the same count and limiting height
  add_test_abort(MovingBodies_ALMTipTravelPhysicalCells_Verify ${_mb_cases}/OpenFAST_ADM_Terrain OpenFAST_ADM_Terrain.i
      "the blade tip sweeps 1[.]11[0-9]* cells per step.*limiting cell height 41[.]65"
      "erf.moving_bodies.T1.mode=alm erf.moving_bodies.T1.fllc=false erf.moving_bodies.verify_tip_cells=1")
  foreach(_t MovingBodies_AnchorLevelAboveFinest MovingBodies_StopTimeNotWholeSteps MovingBodies_ImmersedForcingTerrainRefused MovingBodies_InitShrinkRefused MovingBodies_CtDiskDensityMismatch
             MovingBodies_MixedTimeSteps_OneRank
             MovingBodies_FinerLevelOverTheBodies MovingBodies_FPETrapsRefused MovingBodies_CorrectionRelaxOutOfRange MovingBodies_FllcRelaxAboveStabilityBound
             MovingBodies_ALMTipTravelLimit MovingBodies_ALMTipTravelPhysicalCells MovingBodies_ALMTipTravelStretched
             MovingBodies_ALMTipTravelPhysicalCells_Verify
             MovingBodies_StopTimeNotWholeCoarseSteps
             MovingBodies_AnchorLevelMissingAtStart
             MovingBodies_MaxStepEndsTheRunFirst MovingBodies_NacelleKernelTooNarrow MovingBodies_TowerWidthWithoutTower
             MovingBodies_FllcAutomaticWithEpsilon MovingBodies_FllcAutomaticCellsTooCoarse)
    set_property(TEST ${_t} APPEND PROPERTY LABELS "moving-bodies")
  endforeach()

  # A run that stops at stop_datetime: ERF then ignores stop_time (5 s in the deck), so the
  # turbines must be started for the 7 s to the stop date and the run must reach it (max_step is
  # far beyond, so the date alone ends the run). Before,
  # OpenFAST was started for the deck's stop_time and the run stopped at t = 5.5 s.
  set(_t MovingBodies_StopDatetime)
  set(_dir ${CMAKE_CURRENT_BINARY_DIR}/test_files/${_t})
  file(MAKE_DIRECTORY ${_dir})
  file(GLOB _files "${_mb_cases}/OpenFAST_ADM_Restart/*")
  file(COPY ${_files} DESTINATION "${_dir}/")
  resolve_test_exe("" "erf_exec" TEST_EXE)
  add_test(NAME ${_t} COMMAND sh -c "rm -rf T1_erf.csv moving_bodies && ${MPIEXEC_EXECUTABLE} ${MPIEXEC_NUMPROC_FLAG} 1 ${MPIEXEC_PREFLAGS} ${TEST_EXE} OpenFAST_ADM_Restart.i max_step=100 erf.plot_int_1=-1 erf.check_int=-1 amrex.call_addr2line=0 'start_datetime=\"2020-01-01 00:00:00\"' 'stop_datetime=\"2020-01-01 00:00:07\"' > ${_t}.log 2>&1 && tail -n 1 T1_erf.csv | grep -q '^7,'")
  set_tests_properties(${_t} PROPERTIES TIMEOUT 600 PROCESSORS 1 WORKING_DIRECTORY "${_dir}/"
      LABELS "regression;moving-bodies" ATTACHED_FILES_ON_FAIL "${_dir}/${_t}.log")

  # A run that stops at max_step with no stop_time: the turbines must be started for max_step
  # steps of erf.fixed_dt (4 x 0.5 s = 2 s). Before, ERF's default stop time (the largest double,
  # written into ParmParse by ERF's queryAdd) was read back as the stop time, and OpenFAST was
  # started for 1.797693135e+308 s.
  set(_t MovingBodies_MaxStepWithoutStopTime)
  set(_dir ${CMAKE_CURRENT_BINARY_DIR}/test_files/${_t})
  file(MAKE_DIRECTORY ${_dir})
  file(GLOB _files "${_mb_cases}/OpenFAST_ADM_Restart/*")
  file(COPY ${_files} DESTINATION "${_dir}/")
  file(READ "${_dir}/OpenFAST_ADM_Restart.i" _deck)
  string(REGEX REPLACE "\nstop_time[^\n]*" "" _deck "${_deck}")
  file(WRITE "${_dir}/MaxStepOnly.i" "${_deck}")
  resolve_test_exe("" "erf_exec" TEST_EXE)
  add_test(NAME ${_t} COMMAND sh -c "rm -rf T1_erf.csv moving_bodies && ${MPIEXEC_EXECUTABLE} ${MPIEXEC_NUMPROC_FLAG} 1 ${MPIEXEC_PREFLAGS} ${TEST_EXE} MaxStepOnly.i max_step=4 erf.plot_int_1=-1 erf.check_int=-1 amrex.call_addr2line=0 > ${_t}.log 2>&1 && grep -q 'run stop time 2 s' ${_t}.log && tail -n 1 T1_erf.csv | grep -q '^2,'")
  set_tests_properties(${_t} PROPERTIES TIMEOUT 600 PROCESSORS 1 WORKING_DIRECTORY "${_dir}/"
      LABELS "regression;moving-bodies" ATTACHED_FILES_ON_FAIL "${_dir}/${_t}.log")
  # The same deck with neither stop_time nor max_step: the OpenFAST stop time is unknown, and the run
  # must stop at the start, saying so
  set(_t MovingBodies_NoStopTimeRefused)
  set(_dir ${CMAKE_CURRENT_BINARY_DIR}/test_files/${_t})
  file(MAKE_DIRECTORY ${_dir})
  file(COPY ${_files} DESTINATION "${_dir}/")
  file(WRITE "${_dir}/MaxStepOnly.i" "${_deck}")
  add_test(NAME ${_t} COMMAND sh -c "${MPIEXEC_EXECUTABLE} ${MPIEXEC_NUMPROC_FLAG} 1 ${MPIEXEC_PREFLAGS} ${TEST_EXE} MaxStepOnly.i max_step=-1 erf.plot_int_1=-1 erf.check_int=-1 amrex.call_addr2line=0 > ${_t}.log 2>&1; grep -q 'set stop_time or max_step so the OpenFAST stop time is known' ${_t}.log")
  set_tests_properties(${_t} PROPERTIES TIMEOUT 600 PROCESSORS 1 WORKING_DIRECTORY "${_dir}/"
      LABELS "regression;moving-bodies" ATTACHED_FILES_ON_FAIL "${_dir}/${_t}.log")
endif()


if(ERF_ENABLE_MPI AND NOT WIN32)
  # gale selected in a deck that lists no bodies (the structure-model example's deck)
  add_test_abort(Structures_Abort_GaleNoBodies ${ERF_SOURCE_DIR}/Tests/StructureModelExample inputs_structure_example
                 "erf.structures.model = gale: no bodies are given; list them in erf.moving_bodies.bodies"
                 "erf.structures.model=gale")
  # ERF's own Structures_Abort_NoModelBuiltIn (Submodules/ERF/Tests/CTestList.cmake, not registered
  # in a GALE build) needs no model directory, which a GALE build never has, since Turbines/ is always
  # listed; with Turbines/ the only model, an unknown name must still abort and list what is compiled
  # in, "gale"
  list(LENGTH ERF_STRUCTURE_MODEL_DIRS _gale_n_model_dirs)
  if(_gale_n_model_dirs EQUAL 1)
    add_test_abort(Structures_Abort_NoModelBuiltIn ${ERF_SOURCE_DIR}/Tests/StructureModelExample inputs_structure_example
                   "erf.structures.model = .example. is not one of the structure models compiled in ..gale.."
                   "")
  endif()
  unset(_gale_n_model_dirs)
endif()
