GALE: Generalized Actuator and Loads Engines
============================================

GALE couples bodies that move in the wind to the
`Energy Research and Forecasting (ERF) <https://github.com/erf-model/ERF>`__
atmospheric code. Its first bodies are wind turbines. ERF supplies the wind at
the turbine's blade and tower points. A body solver computes the loads and the
motion. GALE spreads the reaction force back onto the air, so the flow feels
the turbine and forms its wake. Everything in ERF (anelastic dynamics,
terrain-fitted meshes, mesh refinement, LES and RANS closures, the surface
layer) is available to a GALE run.

This repository was the ``ERF-MovingBodies`` branch of ``hgopalan/ERF`` until
November 2026. Its ``development`` branch takes upstream ERF ``development``
merges regularly, so the atmospheric core, build system and inputs stay the
same as ERF's.

==================  ================
Regression Tests     |regtests|
OpenFAST (stub)      |stubtests|
OpenFAST (library)   |realtests|
==================  ================

.. |regtests| image:: https://github.com/erf-model/GALE/actions/workflows/ci.yml/badge.svg?branch=development
.. |stubtests| image:: https://github.com/erf-model/GALE/actions/workflows/openfast-stub.yml/badge.svg?branch=development
.. |realtests| image:: https://github.com/erf-model/GALE/actions/workflows/openfast-real.yml/badge.svg?branch=development

Where the examples are
----------------------

The moving-bodies examples are in ``Exec/CanonicalTests/MovingBodies``. Each
case has its own folder with the input deck and the turbine file, ready to run
with the ``erf_exec`` of a build described under `Building and running`_.

.. list-table::
   :header-rows: 1
   :widths: 34 66

   * - Folder in ``Exec/CanonicalTests/MovingBodies``
     - What it shows
   * - ``Actuator_UniformCtDisk``, ``Actuator_CtDisk_TwoLevel``
     - A prescribed-thrust disk, on one level and on a refined patch. Needs no
       OpenFAST.
   * - ``Actuator_Sampling``, ``OpenFAST_DriverOnly``
     - A turbine that samples the wind without forcing the flow.
   * - ``OpenFAST_ADM_*``
     - Actuator disks: uniform inflow, upstream sampling, terrain, wake lines,
       precursor and perturbation inflow, two turbines, two levels, restart.
   * - ``OpenFAST_ALM_*``
     - Actuator lines: uniform inflow, tower and nacelle, per-component kernel
       widths, the filtered lifting-line correction, restart.
   * - ``OpenFAST_ADM_Askervein``, ``OpenFAST_ALM_Askervein``
     - The IEA 15 MW turbine on the Askervein hill, with the OpenFAST library.
   * - ``OpenFAST_IEA15_PowerCurve``
     - The IEA 15 MW turbine with its ROSCO controller on a flat domain with
       refinement levels, as a disk and as a line, compared with OpenFAST
       alone at five wind speeds. Needs the OpenFAST and ROSCO libraries; not
       run by CTest.
   * - ``IEA15_land_model``
     - The OpenFAST model of the IEA 15 MW turbine used by the Askervein and
       power-curve cases.
   * - ``ScalingFarm``
     - Tools that write and time farms of 16 to more than 1024 turbines.

Every case except the two Askervein cases and the power-curve case runs with
the bundled OpenFAST stub. The Askervein decks expect the ``IEA15_land_model``
folder and the terrain file of ``Exec/CanonicalTests/Real_Terrain/Askervein``
next to them; CTest copies both.
The `cases README <Exec/CanonicalTests/MovingBodies/README.md>`_ lists each
case, its body and what it checks.

What GALE does
--------------

**Body solvers.** Each body named in ``erf.moving_bodies.bodies`` selects its
solver with ``erf.moving_bodies.<name>.type``. Two are available:

* ``openfast_turbine``: a turbine whose aerodynamics, structure and controller
  run in `OpenFAST <https://openfast.readthedocs.io>`_, through its
  external-inflow C interface. OpenFAST 5.0.0 is the tested version; the
  interface is the same in 4.2. Each turbine has its own OpenFAST instance,
  owned by one MPI rank.
* ``ct_disk``: a uniformly loaded disk with a prescribed thrust coefficient.
  It needs no external library and has a closed-form thrust, so it also serves
  as the test body.

**Rotor representations** (``erf.moving_bodies.<name>.mode``) for an OpenFAST
turbine:

* ``adm``, an actuator disk. The blade loads are spread over the swept disk.
  The free-stream speed can be sampled at the disk, upstream of it, or at the
  disk with a filtered-disk correction (the default).
* ``alm``, an actuator line. Each blade is a rotating line of force points,
  with an optional filtered lifting-line correction
  (``erf.moving_bodies.<name>.fllc``; ``automatic`` sets its widths from the
  rotor diameter).
* ``none``, which runs the turbine in ERF's wind without forcing the flow.

Tower and nacelle drag can be added, each with its own kernel width.

**Meshes and levels.** The bodies live on one refinement level, the anchor
level, so a fine patch around a rotor gives an actuator line its few-metre
cells without refining the whole domain. Every coarser level carries the
bodies' force summed onto its faces. Bodies can stand on terrain-fitted meshes.

**Farms.** Any number of bodies can be listed. Each point goes only to the MPI
ranks whose boxes it touches. ``Exec/CanonicalTests/MovingBodies/ScalingFarm``
holds the tools that write and time farms of 16 to more than 1024 turbines.

**Inflow.** Uniform or sheared inflow, turbulent inflow from precursor planes,
and the cell perturbation method.

**Output and restart.** Per-body diagnostics files (loads, sampled flow,
correction logs), wake lines with running averages, body statistics, plotfile
variables, phase timers, and checkpoint and restart of the bodies' state.

**Start-up checks.** A run stops at start-up, naming the input to change, when
a requirement below is not met or an input is out of range.

Requirements of a run
---------------------

* The anelastic solver (``erf.compressibility_type = Anelastic`` or
  ``PseudoIncompressible``) on every level, with a fixed time step.
* The step on the anchor level is a whole multiple of every OpenFAST model's
  time step.
* No finer level may cover a body.
* With an ``openfast_turbine``, the AMReX floating-point traps are off, since
  OpenFAST raises exceptions of its own. Runs with ``ct_disk`` bodies only may
  trap.
* The OpenFAST model sets ``CompInflow = 2`` (external inflow).

Building and running
--------------------

GALE builds with CMake exactly like ERF; the ERF
`Getting Started <https://erf.readthedocs.io/en/latest/GettingStarted.html>`_
page gives the system requirements. Clone with the submodules::

   git clone --recursive https://github.com/erf-model/GALE.git GALE
   cd GALE

To try the coupling without OpenFAST, build against the bundled stub library::

   cmake -S . -B cmake-build -DERF_ENABLE_MPI=ON -DERF_ENABLE_FFT=ON \
         -DERF_ENABLE_OPENFAST=ON -DERF_OPENFAST_USE_STUB=ON
   cmake --build cmake-build -j

For real turbines, install OpenFAST once and point the build at it::

   Build/setup_openfast.sh --no-cpp-api          # prints the OPENFAST_DIR to use
   cmake -S . -B cmake-build -DERF_ENABLE_MPI=ON -DERF_ENABLE_FFT=ON \
         -DERF_ENABLE_OPENFAST=ON -DOPENFAST_DIR=<install prefix>
   cmake --build cmake-build -j

``ERF_ENABLE_MOVING_BODIES=ON`` alone builds the framework with the ``ct_disk``
body and no OpenFAST. A deck turns the bodies on by listing them in
``erf.moving_bodies.bodies``; every ``erf.moving_bodies.*`` key is in the inputs
documentation.

Cases and tests
---------------

``Exec/CanonicalTests/MovingBodies`` has one folder per case, with the input
deck, the turbine file and the gold logs, and a README that lists what each
case checks. The cases run under CTest:

* label ``moving-bodies``: the stub and ``ct_disk`` cases, their restart and
  box-parity twins, and one abort test per start-up check;
* label ``openfast-real``: the IEA 15 MW turbine as a disk and as a line on the
  Askervein hill, against the OpenFAST library.

The unit tests of the samplers, the force spreading, the body exchange and the
OpenFAST driver are in ``Tests/Unit/MovingBodies``.

Data and acknowledgements
-------------------------

The real-OpenFAST cases use the OpenFAST model of the IEA Wind 15 MW reference
turbine, from the IEA Wind Task 37 repository
(https://github.com/IEAWindTask37/IEA-15-240-RWT, Apache License 2.0). We thank
the IEA Wind Task 37 authors for making it available. A land-based copy with
the changes needed for the coupling is redistributed in
``Exec/CanonicalTests/MovingBodies/IEA15_land_model``; its README lists the
source commit and every change, file by file.

We thank the OpenFAST developers for the external-inflow interface the coupling
is built on.

Documentation
-------------

The theory is in ``Docs/sphinx_doc/theory/MovingBodies.rst``, the inputs in the
``erf.moving_bodies`` table of ``Docs/sphinx_doc/Inputs.rst``, and the tests in
``Docs/sphinx_doc/RegressionTests.rst``, alongside the ERF documentation. There
is no published site yet; build them locally with::

   pip install -r Docs/sphinx_doc/requirements.txt
   sphinx-build -b html Docs/sphinx_doc cmake-build/docs

How GALE relates to ERF
-----------------------

ERF holds a coupling interface for models of structures in the flow
(``Source/MovingBodies/Coupling``) and the shared sampling and force-spreading
tools (``Source/MovingBodies/Core``). A model outside ERF registers with that
interface by name, and adding one changes no file of ERF.

Today GALE's turbine module sits in ``Source/MovingBodies`` and is called from
ERF's time step directly. The planned next step is to move it behind the ERF
interface and to put the body solvers behind one interface inside GALE, so that
OpenFAST becomes one engine among others that can be added the same way.

Development model
-----------------

Development happens on topic branches off ``development`` with pull requests
back into ``development``. A new capability comes with a regression case and a
row in the cases README. Fixes to the shared atmospheric core are contributed
to upstream ERF and reach this repository through the periodic upstream merges.
The ERF coding conventions in `CONTRIBUTING.md <CONTRIBUTING.md>`_ apply here
as well.

Built on ERF
------------

ERF, the Energy Research and Forecasting code (`erf-model/ERF
<https://github.com/erf-model/ERF>`_), solves the atmospheric equations in
compressible or anelastic form on the `AMReX <https://amrex-codes.github.io/amrex/>`_
block-structured adaptive mesh framework, from laptops to GPU systems. Its
`ERF documentation <https://erf.readthedocs.io/en/latest/>`_ and
`Doxygen pages <https://erf-model.github.io/docs/index.html>`_ describe the
atmosphere GALE runs in; its Python pre- and post-processing tools are in the
`erftools repository <https://github.com/erf-model/erftools/>`_.

.. image:: https://zenodo.org/badge/DOI/10.5281/zenodo.8102984.svg
   :target: https://doi.org/10.5281/zenodo.8102984

The development of ERF is funded by the U.S. Department of Energy (DOE). When
using GALE, please cite the ERF publications listed at that DOI and the ERF
model paper in JAMES (`doi:10.1029/2024MS004884
<https://doi.org/10.1029/2024MS004884>`_).

GALE is distributed under the ERF license; see `LICENSE.md <LICENSE.md>`_.
