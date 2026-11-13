# GALE: moving bodies (OpenFAST turbines and prescribed-Ct disks) for ERF.
#
# ERF is a git submodule (Submodules/ERF). This file adds it with add_subdirectory and
# compiles GALE's model folder, Turbines/, into it as ERF structure model "gale" through
# ERF's structure-model hooks (ERF_STRUCTURE_MODEL_DIRS). The pattern is ERF's own
# parent-project test, Submodules/ERF/Tests/ParentProject.
#
#   git submodule update --init --recursive
#   cmake -S . -B <build dir> -DERF_ENABLE_MPI=ON -DERF_ENABLE_OPENFAST=ON -DERF_OPENFAST_USE_STUB=ON
#   cmake --build <build dir>
#
# Every ERF option (ERF_ENABLE_MPI, ERF_ENABLE_CUDA, ERF_ENABLE_FFT, ...) is given here as
# it is given to ERF. The executable is <build dir>/ERF/Exec/erf_exec.

# 3.25, as ERF's internal AMReX. (3.21 is the least for the normal variables set below:
# it has policy CMP0126, without which ERF's set(... CACHE ...) drops
# ERF_STRUCTURE_MODEL_DIRS on the first configure.)
cmake_minimum_required(VERSION 3.25)
project(GALE CXX C)

set(GALE_ERF_DIR "${PROJECT_SOURCE_DIR}/Submodules/ERF" CACHE PATH
    "ERF source tree to add with add_subdirectory (default: the Submodules/ERF submodule)")
if(NOT EXISTS "${GALE_ERF_DIR}/CMake/BuildERFExe.cmake")
  message(FATAL_ERROR "GALE_ERF_DIR: ${GALE_ERF_DIR} is not an ERF source tree. "
                      "Run 'git submodule update --init --recursive' first.")
endif()

########################## OPTIONS ##################################

option(ERF_ENABLE_MOVING_BODIES "Enable ERF's actuator core and structure coupling and compile in GALE's moving bodies (Turbines/, erf.moving_bodies.*, structure model gale)" ON)
option(ERF_ENABLE_OPENFAST "Enable the OpenFAST turbine coupling (implies ERF_ENABLE_MOVING_BODIES)" OFF)
option(ERF_OPENFAST_USE_STUB "Build the OpenFAST coupling against the bundled stub library instead of OpenFAST (for testing)" OFF)
option(ERF_BUILD_ROSCO "Download and build the ROSCO turbine controller library (libdiscon) in the build tree; needs ERF_ENABLE_OPENFAST with the OpenFAST library" OFF)
set(ERF_ROSCO_VERSION "2.10.1" CACHE STRING "ROSCO release that ERF_BUILD_ROSCO downloads (a tag of https://github.com/NREL/ROSCO without the leading v)")
set(ROSCO_DIR "" CACHE PATH "Install prefix of a ROSCO controller library built beforehand (Build/setup_rosco.sh): holds lib/libdiscon.so or lib/libdiscon.dylib")
option(ERF_ENABLE_TESTS "Register GALE's regression tests (CTest); ERF's own regression suite is not registered" OFF)
# ERF defaults its unit tests to ERF_ENABLE_TESTS, but ERF is handed ERF_ENABLE_TESTS=OFF below;
# GALE makes the option first, with the same default, so -DERF_ENABLE_TESTS=ON still builds them
option(ERF_ENABLE_UNIT_TESTS "Build ERF's GoogleTest executables with GALE's unit tests in them" ${ERF_ENABLE_TESTS})

########################## OPENFAST ##################################

if(ERF_ENABLE_OPENFAST)
  list(APPEND CMAKE_MESSAGE_CONTEXT "OpenFAST")
  message(STATUS "Configuring OpenFAST")

  # the coupling lives in the moving-bodies framework
  set(ERF_ENABLE_MOVING_BODIES ON CACHE BOOL
      "Enable the moving-bodies actuator framework (erf.moving_bodies.*)" FORCE)

  if(ERF_OPENFAST_USE_STUB)
    # A stand-in for libopenfastlib with the same C API, so the coupling builds and its tests
    # run where OpenFAST is not installed.
    message(STATUS "Using the bundled OpenFAST stub library (ERF_OPENFAST_USE_STUB=ON)")
    add_library(erf_openfast_stub STATIC
      ${PROJECT_SOURCE_DIR}/Turbines/OpenFAST/Stub/ERF_OpenFASTStub.cpp)
    target_include_directories(erf_openfast_stub PUBLIC
      $<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/Turbines/OpenFAST/Stub>)
    install(TARGETS erf_openfast_stub ARCHIVE DESTINATION lib)
  else()
    set(CMAKE_PREFIX_PATH ${OPENFAST_DIR} ${CMAKE_PREFIX_PATH})
    find_package(OpenFAST REQUIRED COMPONENTS openfastlib)
    message(STATUS "Found OpenFAST: ${OpenFAST_INCLUDE_DIRS}")
    # OpenFAST's modules are Fortran, some of them static libraries (libifwlib.a, ...): on Linux ERF's C++
    # link must add the Fortran run-time (libgfortran, ...) itself, which the linker does not take from the
    # shared libraries that need it ("DSO missing from command line"). Turbines/ERFStructureModel.cmake
    # links it. The macOS linker takes it from libopenfastlib, and warns about every library named twice,
    # so it is left out there.
    if(NOT APPLE)
      enable_language(Fortran)
      set(ERF_OPENFAST_FORTRAN_LIBS ${CMAKE_Fortran_IMPLICIT_LINK_LIBRARIES})
      list(REMOVE_DUPLICATES ERF_OPENFAST_FORTRAN_LIBS)
      set(ERF_OPENFAST_FORTRAN_DIRS ${CMAKE_Fortran_IMPLICIT_LINK_DIRECTORIES})
      message(STATUS "OpenFAST Fortran run-time: ${ERF_OPENFAST_FORTRAN_LIBS}")
    endif()
    # ERF uses the OpenFAST 5 external-inflow API only (FAST_ExtInfw_*, unchanged since 4.0); version 3 named it
    # FAST_OpFM_* and is not supported
    # Look again on every configure, so a changed OpenFAST_DIR never keeps the old header
    unset(ERF_OPENFAST_C_HEADER CACHE)
    find_file(ERF_OPENFAST_C_HEADER FAST_Library.h
      PATHS ${OpenFAST_INCLUDE_DIRS} ${OpenFAST_INCLUDE_DIRS}/openfast
      NO_DEFAULT_PATH)
    if(NOT ERF_OPENFAST_C_HEADER)
      message(FATAL_ERROR "FAST_Library.h not found under ${OpenFAST_INCLUDE_DIRS}")
    endif()
    file(STRINGS "${ERF_OPENFAST_C_HEADER}" _erf_openfast_extinfw REGEX "FAST_ExtInfw_Init")
    if(NOT _erf_openfast_extinfw)
      message(FATAL_ERROR "ERF needs OpenFAST 5 (or 4.x): FAST_ExtInfw_Init is not declared in ${ERF_OPENFAST_C_HEADER}")
    endif()
    get_filename_component(ERF_OPENFAST_INCLUDE_DIRS "${ERF_OPENFAST_C_HEADER}" DIRECTORY)
    message(STATUS "OpenFAST C API header: ${ERF_OPENFAST_C_HEADER}")
  endif()

  message(STATUS "OpenFAST configuration complete")
  list(POP_BACK CMAKE_MESSAGE_CONTEXT)
endif()

########################## GALE TURBINES ##############################

# GALE's moving bodies (Turbines/, structure model "gale", with the OpenFAST coupling) are
# compiled in with the moving-bodies framework, whether or not ERF_STRUCTURE_MODEL_DIRS names
# the directory. Relative entries are resolved against ERF's Exec/, as ERF's build_erf_lib does.
if(ERF_ENABLE_MOVING_BODIES)
  set(ERF_GALE_TURBINES_DIR "${PROJECT_SOURCE_DIR}/Turbines")
  get_filename_component(_erf_gale_real "${ERF_GALE_TURBINES_DIR}" REALPATH)
  set(_erf_gale_listed OFF)
  foreach(_d IN LISTS ERF_STRUCTURE_MODEL_DIRS)
    get_filename_component(_d_real "${_d}" REALPATH BASE_DIR "${GALE_ERF_DIR}/Exec")
    if(_d_real STREQUAL _erf_gale_real)
      set(_erf_gale_listed ON)
    endif()
  endforeach()
  if(NOT _erf_gale_listed)
    list(APPEND ERF_STRUCTURE_MODEL_DIRS "${ERF_GALE_TURBINES_DIR}")
  endif()
  message(STATUS "Structure model directories: ${ERF_STRUCTURE_MODEL_DIRS}")
endif()

########################## ROSCO ##################################

# The ROSCO turbine controller (https://github.com/NREL/ROSCO, Apache License 2.0). GALE does not
# link against it: OpenFAST's ServoDyn loads libdiscon at run time when a turbine model names it.
# The path found or built here (ERF_ROSCO_LIBRARY) is for the tests and cases that run such a model.
unset(ERF_ROSCO_LIBRARY CACHE)
unset(ERF_ROSCO_LIBRARY)
if(ERF_BUILD_ROSCO OR ROSCO_DIR)
  list(APPEND CMAKE_MESSAGE_CONTEXT "ROSCO")
  if(NOT ERF_ENABLE_OPENFAST OR ERF_OPENFAST_USE_STUB)
    message(FATAL_ERROR "ERF_BUILD_ROSCO and ROSCO_DIR need ERF_ENABLE_OPENFAST=ON and ERF_OPENFAST_USE_STUB=OFF: "
                        "only the OpenFAST library loads the controller")
  endif()
  if(ERF_BUILD_ROSCO AND ROSCO_DIR)
    message(FATAL_ERROR "Give either ERF_BUILD_ROSCO=ON (build ROSCO here) or ROSCO_DIR=${ROSCO_DIR} (use a built one), not both")
  endif()
  if(ROSCO_DIR)
    find_library(ERF_ROSCO_LIBRARY NAMES discon
                 PATHS "${ROSCO_DIR}/lib" "${ROSCO_DIR}" NO_DEFAULT_PATH)
    if(NOT ERF_ROSCO_LIBRARY)
      message(FATAL_ERROR "ROSCO_DIR=${ROSCO_DIR} holds no lib/libdiscon${CMAKE_SHARED_LIBRARY_SUFFIX}; "
                          "Build/setup_rosco.sh builds one and prints the ROSCO_DIR to give")
    endif()
    message(STATUS "Found the ROSCO controller library: ${ERF_ROSCO_LIBRARY}")
  else()
    if(NOT ERF_ROSCO_VERSION MATCHES "^[0-9]+[.][0-9]+[.][0-9]+$")
      message(FATAL_ERROR "ERF_ROSCO_VERSION must look like 2.10.1, not '${ERF_ROSCO_VERSION}'")
    endif()
    find_package(Git REQUIRED)
    include(ExternalProject)
    set(_erf_rosco_prefix "${CMAKE_BINARY_DIR}/rosco")
    set(ERF_ROSCO_LIBRARY "${_erf_rosco_prefix}/lib/libdiscon${CMAKE_SHARED_LIBRARY_SUFFIX}")
    set(_erf_rosco_args -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${_erf_rosco_prefix})
    if(CMAKE_Fortran_COMPILER)
      # the compiler found for OpenFAST's Fortran run-time, so that both use one run-time library
      list(APPEND _erf_rosco_args -DCMAKE_Fortran_COMPILER=${CMAKE_Fortran_COMPILER})
    endif()
    # part of the default target: "cmake --build <dir>" clones the release tag and builds it;
    # "cmake --build <dir> --target rosco_controller" builds it alone
    ExternalProject_Add(rosco_controller
      GIT_REPOSITORY https://github.com/NREL/ROSCO
      GIT_TAG v${ERF_ROSCO_VERSION}
      GIT_SHALLOW TRUE
      PREFIX "${CMAKE_BINARY_DIR}/rosco-build"
      SOURCE_SUBDIR rosco/controller
      CMAKE_ARGS ${_erf_rosco_args}
      BUILD_BYPRODUCTS "${ERF_ROSCO_LIBRARY}"
      UPDATE_COMMAND ""
      LOG_CONFIGURE ON LOG_BUILD ON LOG_INSTALL ON)
    message(STATUS "ROSCO ${ERF_ROSCO_VERSION} will be downloaded and built as ${ERF_ROSCO_LIBRARY}")
  endif()
  list(POP_BACK CMAKE_MESSAGE_CONTEXT)
endif()

########################## ERF ##################################

# ERF_ENABLE_TESTS registers GALE's regression tests (Tests/CMakeLists.txt). ERF's own suite
# stays off: ERF is handed ERF_ENABLE_TESTS=OFF as a normal variable, which its option() keeps
# (policy CMP0077). ERF_ENABLE_UNIT_TESTS, if on, builds ERF's GoogleTest executables with
# GALE's unit tests in them (Turbines/ERFStructureModel.cmake).
set(_gale_tests ${ERF_ENABLE_TESTS})
set(ERF_ENABLE_TESTS OFF)
if(_gale_tests)
  set(ERF_ENABLE_FCOMPARE ON)   # the plotfile comparisons need amrex_fcompare
endif()

if(_gale_tests OR ERF_ENABLE_UNIT_TESTS)
  enable_testing()
endif()
add_subdirectory("${GALE_ERF_DIR}" ERF)
unset(ERF_ENABLE_TESTS)   # back to the cache value

if(_gale_tests OR ERF_ENABLE_UNIT_TESTS)
  add_subdirectory(Tests)
endif()
