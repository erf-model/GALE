# GNU make for GALE: ERF (Submodules/ERF) with GALE's moving bodies (structure model "gale",
# ../Turbines) compiled in. Run "make" in this folder; the executable and tmp_build_dir are
# written here, not into the submodule. CMake (the top-level CMakeLists.txt) is the tested build.

# AMReX
COMP      = gnu
PRECISION = DOUBLE

# Performance
USE_MPI  = TRUE
USE_OMP  = FALSE
USE_CUDA = FALSE
USE_HIP  = FALSE
USE_SYCL = FALSE

DEBUG         = FALSE
TEST          = TRUE
USE_ASSERTION = TRUE

# The moving-bodies decks use the anelastic solver with the FFT Poisson solver; give
# FFTW_HOME=<FFTW prefix> on the make line if fftw3.h is not on the compiler's default path
USE_FFT = TRUE

# GALE's moving bodies; USE_OPENFAST = TRUE also builds the OpenFAST coupling, with
# OPENFAST_HOME the OpenFAST install prefix (include/FAST_Library.h, lib/libopenfastlib)
USE_MOVING_BODIES = TRUE
USE_OPENFAST      = FALSE
OPENFAST_HOME    ?=

GALE_HOME      := $(abspath ..)
ERF_HOME       := $(GALE_HOME)/Submodules/ERF
STRUCTURE_HOME := $(GALE_HOME)/Turbines

ifeq ($(wildcard $(ERF_HOME)/Exec/Make.ERF),)
    $(error $(ERF_HOME) has no Exec/Make.ERF; run 'git submodule update --init --recursive' first)
endif

# ERF's general problem setup, as ERF's own Exec/GNUmakefile uses
ERF_PROBLEM_DIR = $(ERF_HOME)/Exec
include $(ERF_HOME)/Exec/Make.ERF
