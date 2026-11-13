Building
========

GALE builds with CMake. It adds ERF as a subproject, so every
`ERF build option <https://erf.readthedocs.io/en/latest/buildingSystems.html>`__ works unchanged.
The executable is ``<build>/ERF/Exec/erf_exec``.

Source
------

ERF is a git submodule (``Submodules/ERF``) with its own submodules. A full clone:

.. code-block:: bash

   git clone --recursive https://github.com/erf-model/GALE.git

GALE needs only AMReX, and googletest for the unit tests. A lighter checkout:

.. code-block:: bash

   git clone https://github.com/erf-model/GALE.git && cd GALE
   git submodule update --init Submodules/ERF
   git -C Submodules/ERF submodule update --init Submodules/AMReX Submodules/googletest

Configurations
--------------

.. tab-set::

   .. tab-item:: OpenFAST stub

      No OpenFAST needed. Runs the regression tests.

      .. code-block:: bash

         cmake -S . -B cmake-build -DERF_ENABLE_MPI=ON -DERF_ENABLE_FFT=ON \
               -DERF_ENABLE_OPENFAST=ON -DERF_OPENFAST_USE_STUB=ON
         cmake --build cmake-build -j

   .. tab-item:: OpenFAST library

      Needs a shared, double-precision OpenFAST 5.0 (4.2 also works).
      ``Build/setup_openfast.sh`` builds one and prints the prefix to use.

      .. code-block:: bash

         Build/setup_openfast.sh --no-cpp-api
         cmake -S . -B cmake-build -DERF_ENABLE_MPI=ON -DERF_ENABLE_FFT=ON \
               -DERF_ENABLE_OPENFAST=ON -DOPENFAST_DIR=<prefix>
         cmake --build cmake-build -j

      The OpenFAST library path is stored in the executable's run-time search path. If the
      install moves, add it to ``LD_LIBRARY_PATH`` (Linux) or ``DYLD_LIBRARY_PATH`` (macOS).

   .. tab-item:: Prescribed-Ct disks only

      No OpenFAST coupling at all.

      .. code-block:: bash

         cmake -S . -B cmake-build -DERF_ENABLE_MPI=ON -DERF_ENABLE_FFT=ON
         cmake --build cmake-build -j

The decks use the anelastic solver with the FFT Poisson solve, hence ``ERF_ENABLE_FFT``.

Controller library
~~~~~~~~~~~~~~~~~~

OpenFAST loads a controller at run time from the path in its ServoDyn file. GALE does not link
against it. For `ROSCO <https://github.com/NREL/ROSCO>`__, either run ``Build/setup_rosco.sh``
and pass ``-DROSCO_DIR=<prefix>``, or pass ``-DERF_BUILD_ROSCO=ON`` to build it inside the build
folder. Either one registers the tests labelled ``rosco``.

CMake options
-------------

.. list-table::
   :header-rows: 1
   :widths: 26 54 20
   :class: inputs

   * - Option
     - Effect
     - Default
   * - ``ERF_ENABLE_MOVING_BODIES``
     - Compiles in GALE's bodies (structure model ``gale``) and the ``ct_disk`` body.
     - ON
   * - ``ERF_ENABLE_OPENFAST``
     - Adds the OpenFAST turbine. Set ``OPENFAST_DIR`` to the install prefix. Turns on
       ``ERF_ENABLE_MOVING_BODIES``.
     - OFF
   * - ``ERF_OPENFAST_USE_STUB``
     - Links the bundled stub library (same C API) instead of OpenFAST. For testing.
     - OFF
   * - ``ERF_BUILD_ROSCO``
     - Downloads and builds ROSCO in ``<build>/rosco/lib``. Needs the OpenFAST library, ``git`` and
       a Fortran compiler. Not with ``ROSCO_DIR``.
     - OFF
   * - ``ERF_ROSCO_VERSION``
     - ROSCO release for ``ERF_BUILD_ROSCO``, as ``x.y.z``.
     - 2.10.1
   * - ``ROSCO_DIR``
     - Prefix of a ROSCO build that holds ``lib/libdiscon``. Needs the OpenFAST library.
     - empty
   * - ``ERF_ENABLE_TESTS``
     - Registers GALE's regression tests (:doc:`RegressionTests`). ERF's suite is not registered.
     - OFF
   * - ``ERF_ENABLE_UNIT_TESTS``
     - Builds ERF's GoogleTest executables with GALE's unit tests in them.
     - ``ERF_ENABLE_TESTS``
   * - ``GALE_ERF_DIR``
     - ERF source tree to build against. Must hold ``CMake/BuildERFExe.cmake``.
     - ``Submodules/ERF``

Configure stops with a message when a value is invalid.

GNU Make
--------

``Exec/GNUmakefile`` builds ERF with ``STRUCTURE_HOME`` set to GALE's ``Turbines``. Run
``make -j`` in ``Exec``. GNU Make is not tested in CI.

.. list-table::
   :header-rows: 1
   :widths: 26 54 20
   :class: inputs

   * - Variable
     - Effect
     - Default
   * - ``USE_MOVING_BODIES``
     - Compiles in GALE's bodies.
     - TRUE
   * - ``USE_OPENFAST``
     - Adds the OpenFAST turbine.
     - FALSE
   * - ``OPENFAST_HOME``
     - OpenFAST install prefix, with ``USE_OPENFAST = TRUE``.
     - (none)
   * - ``FFTW_HOME``
     - FFTW prefix, when ``fftw3.h`` is not on the default path.
     - (none)

Updating ERF
------------

GALE builds against the submodule's commit. To move it:

.. code-block:: bash

   git -C Submodules/ERF fetch origin development
   git -C Submodules/ERF checkout <commit>
   git -C Submodules/ERF submodule update --init Submodules/AMReX Submodules/googletest
   git add Submodules/ERF

A weekly CI run builds against the head of ERF ``development``, so an upstream change that
affects GALE shows up before the submodule moves. Its job names end in ``ERF development``. A
plotfile difference there may come from an ERF numerics change; it is regolded when the
submodule moves.

Continuous integration
----------------------

The workflows build GALE with the submodule's ERF and run only GALE's tests. All builds are
double precision and include the OpenFAST stub.

.. list-table::
   :header-rows: 1
   :widths: 24 42 34

   * - Workflow
     - Builds
     - Runs
   * - ``Linux OpenFAST stub``
     - GCC 11, Clang 15; MPI, FFT
     - regression and unit tests
   * - ``Linux GCC OpenFAST 5``
     - GCC; OpenFAST 5.0.0 from source
     - real-OpenFAST cases (``openfast-real``)
   * - ``Linux GPU``
     - CUDA 12.2, HIP ROCm 6.3.2, oneAPI SYCL
     - compile only
   * - ``Windows``
     - MSVC, no MPI; FFTW from vcpkg
     - serial unit tests and four serial regression tests
   * - ``Style``, ``Lint``
     - (none)
     - tabs, trailing whitespace, codespell; actionlint, shellcheck
   * - ``DocHTML -- Build``
     - these pages
     - ``sphinx-build -W``; deploys from ``development``

A compiler warning in a GALE file fails the build job. In the GCC stub job, warnings in ERF files
and linker warnings also fail it. ``.github/workflows/scripts/build_report.sh`` applies these
rules. ``.github/workflows/scripts/run_unit_tests.sh`` fails if one of GALE's unit-test suites is
not linked in.

GPU and Windows CUDA status are listed under :ref:`sec:LimitsBuild`.
