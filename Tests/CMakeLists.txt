# GALE's tests. ERF's own regression suite is not registered (the top-level CMakeLists.txt hands
# ERF ERF_ENABLE_TESTS=OFF); GALE's regression tests are registered here with ERF_ENABLE_TESTS,
# through ERF's general CTest helpers (Submodules/ERF/Tests/ERFTestHelpers.cmake) and GALE's
# copies of the helpers that take more arguments (GaleTestHelpers.cmake). GALE's unit tests are
# built into ERF's GoogleTest executables with ERF_ENABLE_UNIT_TESTS.

if(_gale_tests)
  # The settings ERF's Tests/CMakeLists.txt makes for its own suite, with GALE's gold files
  if(NOT DEFINED ERF_TEST_NRANKS OR "${ERF_TEST_NRANKS}" STREQUAL "")
    set(ERF_TEST_NRANKS 2 CACHE STRING "Number of MPI ranks to use for each regression test" FORCE)
  endif()
  if(NOT ERF_TEST_NRANKS MATCHES "^[1-9][0-9]*$")
    message(FATAL_ERROR "ERF_TEST_NRANKS must be a positive whole number, not '${ERF_TEST_NRANKS}'")
  endif()
  set(ERF_TEST_FCOMPARE_RTOL "2.0e-10" CACHE STRING "fcompare relative tolerance")
  set(ERF_TEST_FCOMPARE_ATOL "2.0e-10" CACHE STRING "fcompare absolute tolerance")
  set(ERF_TEST_GOLD_FILES_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/ERFGoldFiles" CACHE PATH "Path to GALE's gold files")

  find_package(Python3 COMPONENTS Interpreter QUIET)
  if(Python3_Interpreter_FOUND)
    set(ERF_TEST_PYTHON "${Python3_EXECUTABLE}")
  else()
    set(ERF_TEST_PYTHON "")
  endif()

  include("${ERF_SOURCE_DIR}/Tests/ERFTestHelpers.cmake")
  include("${CMAKE_CURRENT_SOURCE_DIR}/GaleTestHelpers.cmake")

  if(ERF_ENABLE_MOVING_BODIES)
    include("${ERF_GALE_TURBINES_DIR}/Tests/ERFTurbinesTests.cmake")
  endif()

  # As ERF's Tests/CMakeLists.txt does for its own suite: one TMPDIR per test.
  # Open MPI 4 keeps one session directory per user under TMPDIR; concurrent mpiexec
  # launches race on it. Open MPI 5 makes the directory unique per launch itself.
  if(ERF_ENABLE_MPI)
    get_property(_gale_reg_tests DIRECTORY PROPERTY TESTS)
    foreach(_gale_test IN LISTS _gale_reg_tests)
      set_property(TEST ${_gale_test} APPEND PROPERTY ENVIRONMENT
        "TMPDIR=${CMAKE_CURRENT_BINARY_DIR}/test_files/${_gale_test}")
    endforeach()
  endif()
endif()

# GALE's parallel unit tests. ERF's erf_parallel_tests has no structure-model hook (its
# erf_unit_tests has one, erf_structure_model_add_unit_tests), so they are added here, after
# ERF made the target.
if(ERF_ENABLE_UNIT_TESTS AND ERF_ENABLE_MOVING_BODIES AND TARGET erf_parallel_tests)
  set(_gale_unit "${ERF_GALE_TURBINES_DIR}/Tests/Unit")
  # Motivation: a turbine's points, sent only to the ranks whose boxes they touch (BodyExchange),
  # must give what the global sampler and spreader give; the cell heights and a uniform mesh's
  # kernel normalisation must not depend on the rank count.
  set(_gale_parallel_sources
    ${_gale_unit}/ERF_GTestBodyExchange.cpp
    ${_gale_unit}/ERF_GTestGaleCellHeights.cpp
    ${_gale_unit}/ERF_GTestGaleUniformMeshNorm.cpp
  )
  if(ERF_ENABLE_OPENFAST AND ERF_OPENFAST_USE_STUB)
    # Motivation: each turbine model is read on one rank at start-up and its checks and sizes handed to
    # every rank; every rank must hold what reading the model itself gives, whichever rank read it.
    list(APPEND _gale_parallel_sources ${_gale_unit}/ERF_GTestModelFacts.cpp)
    target_compile_definitions(erf_parallel_tests PRIVATE
      ERF_GTEST_MOVING_BODIES_CASES="${PROJECT_SOURCE_DIR}/Exec/CanonicalTests/MovingBodies")
  endif()
  target_sources(erf_parallel_tests PRIVATE ${_gale_parallel_sources})
  if(ERF_ENABLE_CUDA)
    # ERF set the language of the target's sources when it made it (CUDA only, as in ERF's
    # BuildERFExe.cmake; HIP and SYCL compile them as CXX); these come later
    set_source_files_properties(${_gale_parallel_sources} TARGET_DIRECTORY erf_parallel_tests
                                PROPERTIES LANGUAGE CUDA)
  endif()
  # ERF's test helper ERF_GTestThrowOnAbort.H, which these tests include
  target_include_directories(erf_parallel_tests PRIVATE ${ERF_SOURCE_DIR}/Tests/Unit/MovingBodies)
endif()
