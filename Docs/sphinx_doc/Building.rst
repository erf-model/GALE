Building
========

GALE takes ERF as a git submodule (``Submodules/ERF``). ERF has its own submodules inside it
(AMReX, googletest, Noah-MP, RRTMGP, WW3 and ekat). Clone with all of them:

.. code-block:: bash

   git clone --recursive https://github.com/erf-model/GALE.git GALE
   cd GALE

A GALE build needs only AMReX, and googletest for the unit tests. A lighter checkout:

.. code-block:: bash

   git clone https://github.com/erf-model/GALE.git GALE
   cd GALE
   git submodule update --init Submodules/ERF
   git -C Submodules/ERF submodule update --init Submodules/AMReX Submodules/googletest

The ERF `Getting Started <https://erf.readthedocs.io/en/latest/GettingStarted.html>`__ page gives
the system requirements, and ERF's
`build options <https://erf.readthedocs.io/en/latest/buildingSystems.html>`__ all work in a GALE
build.

CMake
-----

GALE's ``CMakeLists.txt`` sets its options and then adds ERF as a subproject, the way ERF's
``Tests/ParentProject`` example does. The executable is ``<build>/ERF/Exec/erf_exec``.

To try the coupling without OpenFAST, build against the bundled stub library:

.. code-block:: bash

   cmake -S . -B cmake-build -DERF_ENABLE_MPI=ON -DERF_ENABLE_FFT=ON \
         -DERF_ENABLE_OPENFAST=ON -DERF_OPENFAST_USE_STUB=ON
   cmake --build cmake-build -j

For real turbines, install OpenFAST once and point the build at it:

.. code-block:: bash

   Build/setup_openfast.sh --no-cpp-api          # prints the OPENFAST_DIR to use
   cmake -S . -B cmake-build -DERF_ENABLE_MPI=ON -DERF_ENABLE_FFT=ON \
         -DERF_ENABLE_OPENFAST=ON -DOPENFAST_DIR=<install prefix>
   cmake --build cmake-build -j

``Build/setup_openfast.sh --version 5.0.0`` downloads the release, builds it the way GALE needs
(shared libraries, double precision, the C API on) and installs it under
``$HOME/opt/openfast-<version>`` (``--prefix``, ``--src``, ``--jobs``, ``--fortran`` and
``--configure-only`` are the options). It prints the ``-DOPENFAST_DIR`` to use and the library
path to export at run time.

A turbine model with a controller also needs the controller library, which OpenFAST loads at run
time from the path in its ServoDyn file (``DLL_FileName``). For
`ROSCO <https://github.com/NREL/ROSCO>`__ (``libdiscon``), ``Build/setup_rosco.sh`` builds ROSCO
once and prints the ``ROSCO_DIR`` to give, or ``-DERF_BUILD_ROSCO=ON`` builds it inside the build
folder. GALE does not link against it.

GALE's options, set on the CMake command line with the ERF options:

.. list-table::
   :header-rows: 1
   :widths: 24 56 10 10

   * - Option
     - Effect
     - Default
     - Values
   * - ``ERF_ENABLE_MOVING_BODIES``
     - Enables ERF's actuator core and structure coupling and compiles in GALE's moving bodies
       (``erf.moving_bodies.*``: turbines, prescribed-Ct disks; ``Turbines/``, structure model
       ``gale``)
     - ON
     - ON/OFF
   * - ``ERF_ENABLE_OPENFAST``
     - Enables the OpenFAST turbine coupling (OpenFAST 5.0, tested with 5.0.0 and 4.2.1; set
       ``OPENFAST_DIR`` to the install prefix); turns on ``ERF_ENABLE_MOVING_BODIES``
     - OFF
     - ON/OFF
   * - ``ERF_OPENFAST_USE_STUB``
     - Builds the OpenFAST coupling against the bundled stub library instead of OpenFAST, for
       testing
     - OFF
     - ON/OFF
   * - ``ERF_BUILD_ROSCO``
     - Downloads and builds the ROSCO controller library in the build folder
       (``<build>/rosco/lib``); needs ``ERF_ENABLE_OPENFAST=ON`` with the OpenFAST library,
       ``git`` and a Fortran compiler; cannot be given with ``ROSCO_DIR``
     - OFF
     - ON/OFF
   * - ``ERF_ROSCO_VERSION``
     - The ROSCO release ``ERF_BUILD_ROSCO`` downloads; configure stops if it is not of the form
       ``x.y.z``
     - 2.10.1
     - a release number
   * - ``ROSCO_DIR``
     - Install prefix of a ROSCO library built beforehand (``Build/setup_rosco.sh``); configure
       stops if it holds no ``lib/libdiscon``; needs ``ERF_ENABLE_OPENFAST=ON`` with the OpenFAST
       library
     - empty
     - a path
   * - ``ERF_ENABLE_TESTS``
     - Registers GALE's regression tests (:doc:`RegressionTests`); ERF's own regression suite is
       not registered
     - OFF
     - ON/OFF
   * - ``ERF_ENABLE_UNIT_TESTS``
     - Builds ERF's GoogleTest executables (``<build>/ERF/Tests/Unit``) with GALE's unit tests in
       them
     - ``ERF_ENABLE_TESTS``
     - ON/OFF
   * - ``GALE_ERF_DIR``
     - The ERF source tree to build against; configure stops if it has no
       ``CMake/BuildERFExe.cmake``
     - ``Submodules/ERF``
     - a path

``ERF_ENABLE_MOVING_BODIES`` is ON by default in GALE (it is OFF in ERF). The tests' golds
hold the OpenFAST stub's loads, and the decks use MPI and the FFT Poisson solve. Run them with

.. code-block:: bash

   cmake -S . -B cmake-build -DERF_ENABLE_MPI=ON -DERF_ENABLE_FFT=ON \
         -DERF_ENABLE_OPENFAST=ON -DERF_OPENFAST_USE_STUB=ON -DERF_ENABLE_TESTS=ON
   cmake --build cmake-build -j
   ctest --test-dir cmake-build/Tests --no-tests=error     # GALE's regression tests
   ctest --test-dir cmake-build -L unit --no-tests=error   # the unit tests

GNU Make
--------

``Exec/GNUmakefile`` builds ERF from the submodule with ``STRUCTURE_HOME`` set to GALE's
``Turbines`` and ``USE_MOVING_BODIES = TRUE``. Run ``make -j`` in ``Exec``; the executable and
``tmp_build_dir`` are written there. ``USE_OPENFAST = TRUE`` with ``OPENFAST_HOME`` (the OpenFAST
install prefix) builds the OpenFAST coupling. ``FFTW_HOME=<prefix>`` on the make line points to FFTW
when ``fftw3.h`` is not on the compiler's default path (for example ``/opt/homebrew`` on macOS).
CMake is the tested build; the CI does not build with GNU Make.

.. list-table::
   :header-rows: 1
   :widths: 24 56 10 10

   * - Variable
     - Effect
     - Default
     - Values
   * - ``USE_MOVING_BODIES``
     - Enables ERF's actuator core and structure coupling; with ``STRUCTURE_HOME`` naming
       ``Turbines`` it compiles in GALE's moving bodies
     - TRUE
     - TRUE/FALSE
   * - ``USE_OPENFAST``
     - Builds GALE's OpenFAST turbine coupling (read only by ``Turbines/Make.package``)
     - FALSE
     - TRUE/FALSE
   * - ``OPENFAST_HOME``
     - OpenFAST install prefix (``include/FAST_Library.h``, ``lib/libopenfastlib``), for
       ``USE_OPENFAST=TRUE``
     - (none)
     - a path

Updating ERF
------------

The ERF version GALE builds against is the submodule's commit. To move it:

.. code-block:: bash

   git -C Submodules/ERF fetch origin development
   git -C Submodules/ERF checkout <commit>
   git -C Submodules/ERF submodule update --init Submodules/AMReX Submodules/googletest
   git add Submodules/ERF

The weekly run of the ``Linux OpenFAST stub`` workflow (below) builds against the head of ERF's
``development`` branch, so a change upstream that breaks GALE shows up before the submodule
is moved. Its job names end in ``ERF development``, and its step summary links the ERF changes
since the pinned commit. An fcompare difference in that run can come from a numerics change in
ERF rather than a defect; it is resolved by regolding when the submodule is moved.

Continuous integration
----------------------

GALE's GitHub Actions workflows build GALE with ERF from the submodule and run only GALE's
tests; ERF's own suite runs in ERF's CI. Every build includes GALE's moving bodies and the
OpenFAST coupling against the bundled stub. The hosted runners have no GPU, so the GPU builds
compile and link only: their device kernels are never run. Every build is in double precision.

.. list-table::
   :header-rows: 1
   :widths: 22 40 38

   * - Workflow
     - Builds
     - Runs
   * - ``Linux OpenFAST stub``
     - GCC 11 and Clang 15, MPI, FFT, unit tests
     - GALE's regression tests and unit tests; weekly and on request (``erf_ref``) also
       against ERF's ``development`` head
   * - ``Linux GCC OpenFAST 5``
     - GCC, MPI, FFT, OpenFAST 5.0.0 built from source
     - the real-OpenFAST cases (label ``openfast-real``)
   * - ``Linux GPU``
     - CUDA 12.2 (sm_80) with the unit tests, HIP ROCm 6.3.2 (gfx908), oneAPI SYCL; MPI, FFT
     - compile only
   * - ``Windows``
     - MSVC without MPI, FFT (FFTW from vcpkg), unit tests
     - GALE's serial unit tests and the four GALE regression tests registered without
       MPI (``OpenFAST_DriverOnly`` and the ``ShaftSourceChecker`` cases, none of which runs a
       turbine's forcing on the flow)
   * - ``Style``
     - (nothing)
     - no tabs, no trailing whitespace, codespell, on GALE's files
   * - ``Lint``
     - (nothing)
     - actionlint and shellcheck on the workflows and scripts in ``.github``
   * - ``DocHTML -- Build``
     - this documentation
     - ``sphinx-build -W``; deploys to GitHub Pages from ``development``

A compiler warning in a GALE file fails a build job. In the GCC job of ``Linux OpenFAST stub`` a
warning in an ERF file, or a compiler-driver or linker warning, fails it too, as before; in the
other jobs those are listed but do not fail the job
(``.github/workflows/scripts/build_report.sh``). The unit-test step
(``.github/workflows/scripts/run_unit_tests.sh``) reads GALE's test suites from the files
``Turbines/ERFStructureModel.cmake`` builds into ``erf_unit_tests`` and fails if one of them is
not linked in. Compiler caches use the GitHub Actions cache; they are restored on every run and
saved only on pushes to ``development``.

There is no Windows CUDA job. On Windows, ``nvcc`` refuses an extended ``__device__`` lambda
whose enclosing function has internal linkage, that is a ``static`` function or any function in
an anonymous namespace. Twenty-six of ERF's source files write their kernels that way, so GALE
cannot be compiled for CUDA on Windows until ERF changes. GALE's own two such kernels are
written with external linkage. ``Linux GPU`` compiles the same kernels with ``nvcc``.
