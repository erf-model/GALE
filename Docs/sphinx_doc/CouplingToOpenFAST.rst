
 .. role:: cpp(code)
    :language: c++

 .. _CouplingToOpenFAST:

Coupling To OpenFAST
====================

ERF drives OpenFAST wind turbines as actuator disks or actuator lines through
the moving-bodies framework (``erf.moving_bodies.*``). Each step ERF samples
the wind at the turbine's nodes, hands it to OpenFAST through the
FAST_Library C interface (the ExtInfw inflow path), steps the turbine in
lockstep with its own time step, and spreads the returned loads into the flow
as a momentum source. The physics and the choices behind it are described in
:doc:`the theory chapter <theory/MovingBodies>`;
this page is the how-to.

Building
--------

Build OpenFAST 5.0 (4.2 also works) as a shared library, which produces
``FAST_Library.h``; the C++ API is optional (``--no-cpp-api`` skips it). ``Build/setup_openfast.sh`` does this
in one command (``--force`` rebuilds an existing install); by hand:

.. code-block:: bash

   cmake -DBUILD_OPENFAST_CPP_API=OFF -DBUILD_SHARED_LIBS=ON -DDOUBLE_PRECISION=ON \
         -DCMAKE_INSTALL_PREFIX=$HOME/opt/openfast-5.0.0 ..
   make -j4 install

Then configure GALE with the coupling (:doc:`Building`). The moving-bodies framework is switched on
by ``ERF_ENABLE_OPENFAST``; prescribed-Ct disks alone need only
``ERF_ENABLE_MOVING_BODIES`` and no OpenFAST. The decks use the anelastic
solver with the FFT Poisson solve:

.. code-block:: bash

   cmake -S . -B cmake-build -DERF_ENABLE_MPI=ON -DERF_ENABLE_FFT=ON -DERF_ENABLE_OPENFAST=ON \
         -DOPENFAST_DIR=$HOME/opt/openfast-5.0.0

The CMake build records the OpenFAST library directory in ``erf_exec``'s run-time
search path; a moved installation or another build system needs it on the loader
path (``DYLD_LIBRARY_PATH`` on macOS, ``LD_LIBRARY_PATH`` on Linux). Without an
OpenFAST installation, ``-DERF_OPENFAST_USE_STUB=ON`` builds against a bundled
stub library with the same C API; most regression tests run on it, and so does
the GCC and Clang jobs of the ``Linux OpenFAST stub`` CI workflow. Two cases run the real library on the
IEA 15 MW reference turbine (below); the ``Linux GCC OpenFAST 5`` CI job builds
OpenFAST 5.0.0 with ``Build/setup_openfast.sh`` (cached between runs) for them.

A turbine model whose ServoDyn file names a controller library also needs
that library at run time. For the ROSCO controller
(https://github.com/NREL/ROSCO), ``Build/setup_rosco.sh`` downloads release
2.10.1, builds ``libdiscon`` and installs it under ``$HOME/opt/rosco-2.10.1``;
``-DROSCO_DIR=<prefix>`` then tells the build where it is. Alternatively
``-DERF_BUILD_ROSCO=ON`` downloads and builds it inside the build folder
(``<build>/rosco/lib``; ``ERF_ROSCO_VERSION`` picks the release). ERF does not
link against ROSCO: the ServoDyn file names the library (``DLL_FileName``), and
the two options make its path known to tests that run such a model. Both need
the OpenFAST library, not the stub.
The tests of
``Exec/CanonicalTests/MovingBodies/OpenFAST_IEA15_PowerCurve`` (label
``rosco``) use it.

Floating-point traps must stay off in a run with an OpenFAST turbine
(``amrex.fpe_trap_invalid``, ``amrex.fpe_trap_zero`` and
``amrex.fpe_trap_overflow`` all 0): OpenFAST's own arithmetic raises them.

The bodies need a mesh whose map factors are all 1: their forces are spread
and the velocities sampled at ``prob_lo + i dx`` with the cell volumes
``dx dy dz detJ``. A run whose anchor level has a map factor other than 1
stops with a message that says so (checked at every step of that level).

Preparing the turbine model
---------------------------

The OpenFAST model is a standard set of files (``.fst``, ElastoDyn, AeroDyn,
ServoDyn or a fixed rotor speed). Four settings matter for the coupling:

- ``CompInflow = 2`` in the ``.fst``: the inflow comes from ERF.
- ``AirDens`` in the ``.fst`` equal to ERF's density at the hub; the start-up
  audit aborts when they differ by more than ``erf.moving_bodies.density_tolerance``.
- ``Wake_Mod`` in the AeroDyn file: ``0`` for ``sampling = disk``, which is
  also what the actuator line uses (the resolved flow carries the induction),
  non-zero (``1``, BEMT) for ``sampling = disk_corrected`` (the disk's
  default) and ``sampling = upstream``, where OpenFAST applies its own
  induction to the free stream ERF hands it. The start-up check aborts on the wrong pairing, so one
  model file serves either the disk or the line, not both.
- Tower shadow off (``TwrShadow = 0``) when tower force points are used: the
  tower's wake reaches the blades through the flow.

The bodies' step, ``erf.fixed_dt`` divided by the time refinement down to the
anchor level (``erf.fixed_dt`` itself on one level), must be a whole multiple of
OpenFAST's ``DT``; the coupling sub-steps OpenFAST accordingly. With
``DT = 0.005`` s, ``erf.fixed_dt = 0.15`` works on two levels (0.075 s) but not
on three (0.0375 s); 0.16 works on three (0.04 s). The start-up aborts
otherwise.

A minimal case
--------------

A single IEA 15 MW rotor as an actuator disk in a uniform inflow on a
20 m mesh, the configuration calibrated against the standalone OpenFAST
solution. Its AeroDyn file sets ``Wake_Mod = 1``, as the default
``sampling = disk_corrected`` needs:

.. code-block:: text

   erf.compressibility_type = Anelastic
   erf.timestepping_type = MidPoint   # honours the implicit vertical solve (RK2 does not)
   erf.vert_implicit  = true
   erf.use_fft        = true
   erf.fixed_dt       = 0.2          # on the anchor level: a whole multiple of OpenFAST's DT
   amrex.fpe_trap_invalid = 0

   erf.structures.model                         = gale         # the bodies as ERF's structure model
   erf.moving_bodies.bodies                     = T1
   erf.moving_bodies.T1.type                    = openfast_turbine
   erf.moving_bodies.T1.mode                    = adm          # or alm
   erf.moving_bodies.T1.fst_file                = IEA15-land.fst
   erf.moving_bodies.T1.base_pos                = 750. 600. 0. # z above the terrain surface
   erf.moving_bodies.T1.num_force_points_blade  = 50
   erf.moving_bodies.T1.num_points_t            = 24
   erf.moving_bodies.T1.epsilon                 = 2.0          # disk: kernel width in cells
   # for an actuator line (mode = alm) leave out epsilon and num_force_points_blade and set
   # erf.moving_bodies.T1.fllc = automatic (see "Choosing the model and its settings")
   erf.moving_bodies.T1.output_root             = T1
   erf.moving_bodies.diagnostics_dir            = moving_bodies

The complete list of inputs, with their defaults, is in the
"Moving Bodies (OpenFAST turbines)" section of :doc:`Inputs <Inputs>`.
The canonical decks under ``Exec/CanonicalTests/MovingBodies`` are the
runnable reference for every feature (disk, line, tower, farm, wake lines,
turbulent inflow, two levels, terrain, restart).

Choosing the model and its settings
-----------------------------------

The first table shows how close each disk set-up came to the standalone
OpenFAST (BEM) loads of the IEA 15 MW in a uniform 10.59 m/s inflow, with the
rotor speed held fixed.

======================================================  ==================  ==================
Set-up                                                  thrust / BEM        power / BEM
======================================================  ==================  ==================
disk, ``disk_corrected`` (default), 20 m or 10 m cells  0.997 to 1.001      0.993 to 1.000
disk, ``upstream`` sampling two diameters ahead          0.993               0.999
disk, plain ``disk`` sampling, 20 m cells                1.093               1.328
======================================================  ==================  ==================

The second table compares the disk and the line with the standalone OpenFAST 5
solution of the IEA 15 MW land-based turbine under the ROSCO controller, at five
uniform wind speeds. The ERF runs are averaged over 300 to 360 s and OpenFAST
over 120 to 700 s, following the Kynema-SGF actuator-line calibration
(G. R. Yalla, ``gyalla/ALM_Calibrations``). Each entry is the error in power /
thrust. The line uses ``fllc = automatic``: a kernel of 0.035 rotor diameters
(8.4 m), ``fllc_eps_chord = 0.15`` and 300 points per blade. Above rated
(10.6 m/s) the controller holds power and rotor speed, so thrust is the test.
The decks, the controller inputs and the scripts that make the runs and the
comparison are in ``Exec/CanonicalTests/MovingBodies/OpenFAST_IEA15_PowerCurve``;
the ROSCO library itself is not in the repository.

======  =====================  =====================  =====================
U       disk, 20 m (1 level)   line, 10 m (2 levels)  line, 5 m (3 levels)
======  =====================  =====================  =====================
5.0     -0.2 % / -0.1 %        +1.4 % / +0.6 %        +3.7 % / +1.6 %
6.5     -0.2 % / -0.1 %        -1.1 % / -0.4 %        +1.3 % / +0.7 %
9.0     -0.2 % / -0.1 %        -3.8 % / -1.9 %        -1.1 % / -0.4 %
11.0    0.0 % / +0.1 %         0.0 % / +6.6 %         0.0 % / +4.3 %
14.0    0.0 % / 0.0 %          0.0 % / +2.5 %         0.0 % / +2.0 %
======  =====================  =====================  =====================

- **Disk or line.** The corrected disk is the default and matches BEM on
  every grid tried; use it for farms and RANS or ABL studies. The actuator
  line, with the FLLC, is the choice for LES that resolves the blades. With
  ``fllc = automatic`` it stays within 5 % of OpenFAST on 10 m and 5 m cells
  for the IEA 15 MW, except the 11 m/s thrust on 10 m cells (+6.6 %).
- **The corrected disk's update.** The recovered free stream is updated each
  step from the last one, through the induction the thrust implies. Above a
  thrust coefficient of about 0.75 that update overshoots and grows step by
  step; and the flow answers a change of thrust only after a delay, which can
  make the update ring at a period of seconds. By default it is therefore
  under-relaxed by a factor taken from its own loop gain, and limited so that
  an error decays on the time scale of the rotor radius over the free stream
  (``correction_relax = -1``, ``correction_time = -1``); the relaxation changes
  how the free stream is reached, not where it settles, at the cost of a
  start-up of tens of seconds instead of a few steps. ``correction_relax = 1`` gives the unrelaxed update
  for comparison. The theory chapter has the derivation.
- **Kernel width.** For the corrected disk keep the filter width
  :math:`\sqrt{6}\,\epsilon` within 1.25 rotor radii (a 1.5-cell kernel on
  40 m cells for a 120 m rotor); the start-up log warns otherwise. For the
  line, hold the kernel at a fixed length as the mesh is refined, not at a fixed
  number of cells: 0.035 rotor diameters (8.4 m for the IEA 15 MW), the bound of
  Sandia report SAND2021-15447C. ``epsilon`` is given in cells of the anchor
  level's x spacing, so 8.4 m is 0.84 on 10 m cells and 1.68 on 5 m cells;
  ``fllc = automatic`` does this conversion. Held at 0.8 cells instead, the
  kernel is 2 m on 2.5 m cells, and the line gives 15 % less power than
  OpenFAST at 5 m/s. At a fixed kernel length the 5 m mesh reads 2.4 to
  2.7 points above the 10 m mesh in power below rated, and 0.5 to 2.3 points
  below it in thrust above rated; at 5 m/s the upwinding, the FLLC correction,
  the tip treatment and the size of the refined box each change the gap by
  0.1 points or less. A kernel below about 0.75 cells still puts
  exactly the force into the flow, but its shape depends on where the point
  sits in its cell (see the theory chapter).
- **FLLC** is on by default for the line (``fllc = false`` switches it off)
  and is the generalized variable-chord form. ``fllc = automatic`` sets the
  kernel to 0.035 rotor diameters (twice the tip radius of the model's files,
  ElastoDyn ``TipRad``),
  ``fllc_eps_chord = 0.15`` (the lower end of the optimal range 0.1 to 0.25),
  ``fllc_eps_dr = 3``, ``fllc_start_time = 5`` s and
  ``num_force_points_blade = 300``, and prints the values. Giving any of those
  keys with it aborts; use ``fllc = true`` to set them by hand (an
  ``fllc = true`` on the command line overrides an ``automatic`` in the deck,
  and the defaults then apply). The kernel must be at least 0.75 cells, so the
  anchor level's cells at most 0.047 rotor diameters (11.2 m for the
  IEA 15 MW); below that the spread kernel's width depends on where a node sits
  in its cell, and automatic aborts. With 50 points per blade instead of 300
  the line gives about 2.5 points less power on every mesh tried. These
  settings were tested on cells with ``dx = dy = dz``; on an anchor level with
  other proportions the start-up prints a note.
- **Time step for the line.** The blade tip may sweep at most
  ``erf.moving_bodies.alm_max_tip_cells`` cells per step (1 by default); the
  start-up names the largest ``erf.fixed_dt`` that passes. For the IEA 15 MW
  ``erf.fixed_dt = 0.2`` sweeps 0.95 cells at the rated 7.56 rpm on the 10 m
  mesh (and the same on 5 m: half the cell, half the step), a 5 % margin that
  the rotor's speed early in the run used up (1.006 cells at t = 4 s, about
  8 rpm), so
  0.15 (10 m) and 0.16 (5 m) were used at 11 and
  14 m/s, keeping the anchor step a whole multiple of OpenFAST's ``DT``.
- **Grids.** The rotor should span at least 8 cells (the audit notes fewer).
  On a run with refinement the bodies live on the anchor level
  (``amr.max_level`` by default), whose grids must cover every node with the
  kernel's reach, and no finer level may cover them. Every coarser level carries
  the same force, summed onto its own faces, so the induction reaches beyond
  the refined box. On a terrain-fitted mesh
  the cells the kernel's heights may lie in are those of the node's own
  columns, so the level's top need only clear each rotor's kernel where the
  rotor stands, whatever the terrain elsewhere on the level.
- **Boundary conditions.** Inflow at ``xlo`` and outflow at ``xhi`` with a
  sounding or a precursor profile; a periodic box lets the wake feed the
  inflow. No sponge layer around a single turbine. CFL at or below 0.5.
- **Terrain.** On a terrain-fitted mesh ``base_pos`` z is the height above
  the surface at the base; the bodies are placed on the terrain at start-up.

Outputs
-------

Per turbine, under ``output_root``, every ``diagnostics_int`` steps:

- ``<root>_erf.csv``: rotor speed (signed like the torque about the shaft),
  thrust vector, torque, power, hub axis, tower and nacelle forces and total
  load.
- ``<root>_flow.csv``: the velocities handed to OpenFAST at the hub and the
  blade mean, after the sampling correction and the FLLC.
- ``<root>_correction.csv`` (``disk_corrected``): disk velocity, inferred
  thrust coefficients, induction, correction factor, recovered free stream,
  the update's loop gain and the relaxation used.
- ``<root>_fllc.csv`` (line with FLLC): the correction's magnitude.
- ``<root>_wake.csv`` and ``<root>_wake_avg.csv`` (``erf.moving_bodies.wake.*``):
  instantaneous and running-averaged velocity along lateral and vertical lines
  downstream.
- ``<root>_stats.csv``: running statistics from ``avg_start`` on, rewritten
  whole at each write (every ``stats_int`` steps, at checkpoints and at the
  end, when ``stats_int`` is set).
- ``<diagnostics_dir>/total_load.csv``, ``momentum_source.csv``,
  ``ground.csv``: farm totals, the integrated source (equal to minus the
  loads; for an actuator disk on a tilted shaft, minus the thrust's shaft
  component (T . n) n, since its rings cancel the in-plane load), the terrain
  height under each body.

The rows of ``_erf.csv``, ``_flow.csv`` and ``total_load.csv`` carry the time
at the end of their step; the others carry the time at the start of the step
whose forcing they describe. The full list, with the prescribed-Ct disk's
file, is under the input table in :doc:`Inputs <Inputs>`. OpenFAST writes its
own ``.out`` and summary files next to the ``.fst``.

``erf.moving_bodies.diagnostics_format`` gathers the per-turbine time series
and statistics into one file per rank (``per_rank``) or one per log for the
whole farm (``farm``, written by the I/O rank), with the body's name as a
column; the default ``per_turbine`` writes the files above. In every format
each file is opened once and kept open, and its rows are flushed at every
checkpoint and at the end of the run.

Running on many ranks
---------------------

Each turbine is owned by one rank, which alone runs its OpenFAST model and
writes its logs: a rank whose boxes it stands on, unless that would give one
rank more turbines than another or mix two OpenFAST time steps, in which case a
nearby rank with fewer turbines takes it. Its points go only to the ranks whose
boxes they touch, so a rank far from every turbine samples and spreads nothing
for it (it still joins two integer reductions per step). The run log names each
turbine's and disk's owner and the ranks it, and the wake lines behind it,
exchange with. The turbines a rank owns are
stepped in turn, so they must use the same OpenFAST ``DT`` (turbines of
different ``DT`` get different ranks whenever there are at least as many ranks
as distinct ``DT``), and a rank that owns several turbines steps their models
one after the other: run a farm on at least as many ranks as it has turbines. A check on a turbine's points stops
the run from its owner's rank, whose message is the one to read. Each
prescribed-Ct disk has an owner too, chosen by the same rule among the disks
alone (a disk runs no model, so it may share a rank with a turbine), which
samples the flow for it, sets its thrust and writes its log and statistics.
The wake lines behind a rotor belong to the rotor's owner, which samples them,
keeps their running average and writes their files; sampling them adds one
integer reduction at each step that writes them.

At start-up each distinct ``.fst`` (a farm usually shares a few models, or
gives each turbine its own) is read by one rank only, the distinct files
spread over the ranks, each of its files once: the ``Wake_Mod`` and
``TwrShadow`` checks and the rotor's radius and time step. One gather hands
every rank the results, so a check fails on every rank alike, with the same
message. A turbine's owner reads its model once more, each file once, for the
start-up audits. At each diagnostics step the
farm's totals (``total_load.csv``) and, in the ``farm`` format, every body's
rows reach the I/O rank in one reduction.

For large farms (hundreds of turbines and more):

- Write the diagnostics less often than every step: ``diagnostics_int`` of 10
  to 100 steps (a few seconds of simulated time) resolves the rotor dynamics
  the logs are used for, and OpenFAST's own ``.out`` files keep the full rate.
  Set ``avg_start`` so the statistics, rewritten at each write (or every
  ``stats_int`` steps), start after the spin-up.
- Sample wake lines rarely: their exchange costs a collective every
  ``wake.int`` steps. Use a multiple of ``diagnostics_int``, 50 to 200 steps
  for averaged wake profiles, and only behind the turbines whose wakes are
  studied.
- Use ``diagnostics_format = farm`` (or ``per_rank`` when the farm file's
  gather to one rank is too large): a few files in place of several per
  turbine.
- Rewrite the summary files rarely: each statistics file (``_stats``) and
  each wake-average file (``_wake_avg``) is written afresh in full, by
  default at every diagnostics step and every wake sample. ``stats_int`` of
  a few hundred steps rewrites them that often, and also at every checkpoint
  and at the end of the run, so they hold every sample at those points.
- Each rank keeps its logs open from one row to the next, at most
  ``max_open_logs`` of them (by default a quarter of the process's limit on
  open files). An owner of more logs than that finds about
  ``max_open_logs - 1`` of them still open at their next row and closes and
  opens the others again, which is slower but writes the same files; raise the limit
  (``ulimit -n``) or use ``per_rank`` or ``farm`` for many bodies per rank.
- Measure before tuning: ``timing_int`` prints the time of each phase (the
  sampling, OpenFAST, the spreading, the diagnostics, the wake lines) over
  the ranks every few steps, and a build with
  ``-DERF_ENABLE_TINY_PROFILE=ON`` breaks it down further, down to each
  message round of the exchanges (see the theory section on timing).

Restarting
----------

Checkpoints hold the OpenFAST state and every running quantity, so a restart
continues bit for bit. It must continue the same bodies with the same inputs,
the same ``erf.fixed_dt`` and a stop time no later than the one the turbines
were started with (OpenFAST keeps that stop time in its own checkpoint); the
run aborts otherwise, naming the input. The diagnostics files drop any rows
written after the checkpoint (by a run that went on past it) and continue from
there (in the ``per_rank`` format, the files of every rank of either run; a
restart in another ``diagnostics_format`` starts that format's files and leaves
the old ones as they are). Each file is cut by the rank that writes it in the
restarted run (a body's owner its files, each rank its ``per_rank`` files, the
I/O rank the farm files, the run's own and the ``per_rank`` files of ranks the
restarted run does not have), reading back from the file's end to the
checkpoint, so a long log costs only the rows written after it. The cut assumes
the rows are in time order, as ERF writes them; a file that went back and forth
between two formats over several restarts may not be. To run on past the first run's stop time, start the turbines again:
remove the ``moving_bodies`` directory from a copy of the checkpoint and restart
from that copy, which starts OpenFAST afresh at the checkpoint's time (and also
starts the wake averages, the statistics and the FLLC afresh). A run with
prescribed-Ct disks only may simply restart with a later stop time. A run started from a precursor checkpoint written
without bodies starts the turbines at the checkpoint's time; a run that stops
at ``stop_datetime`` hands OpenFAST the seconds to the stop date.

Tests
-----

.. code-block:: bash

   ctest --test-dir cmake-build/Tests -L moving-bodies   # the canonical cases and the start-up aborts
   ctest --test-dir cmake-build/Tests -L restart-parity -R "OpenFAST|MovingBodies"
   ctest --test-dir cmake-build/Tests -L box-parity -R "OpenFAST|Actuator"
   .github/workflows/scripts/run_unit_tests.sh cmake-build/ERF/Tests/Unit/erf_unit_tests   # GALE's and ERF's moving-bodies unit tests
   ctest --test-dir cmake-build -L parallel -R "Actuator|BodyExchange"   # the same exchanges on 1, 2 and 4 ranks

These CTests run on the stub library (``-DERF_OPENFAST_USE_STUB=ON``); their
golds hold the stub's loads. With a real OpenFAST the same decks run, but the
loads, and so the golds, differ. A build against the real library
(``-DERF_OPENFAST_USE_STUB=OFF``) registers two other cases instead, label
``openfast-real``: the IEA 15 MW reference turbine (the model is in
``Exec/CanonicalTests/MovingBodies/IEA15_land_model``) on the Askervein hill as
an actuator disk and as an actuator line with its tower and nacelle:

.. code-block:: bash

   ctest -L openfast-real

Known limits
------------

- The corrected disk's inferred thrust coefficient sits at its 0.96 clamp
  when the rotor spans only 6 cells; the recovered free stream is then a
  few percent low.
- A fine level whose boundary coincides with the inflow face gave an
  anomalous stable-ABL result; keep refinement patches away from the inflow.
- With a Dirichlet theta profile at the inflow, do not set ``<face>.density``
  in an anelastic run: the inflow theta is scaled by the density ratio.
- The k-equation length-scale cap from the PBL height reads each level's own
  diagnosis; pin ``erf.max_geom_lscale`` on multi-level ABL runs.
- Refined levels on a terrain-fitted mesh with turbines: a 100 m Gaussian hill
  with four levels (160, 80, 40 and 20 m across, refinement ``2 2 1``, the
  refined levels stopping at 800, 720 and 640 m of the 960 m domain,
  ``erf.coupling_type = OneWay``, the default ``gmres_fft`` solver) ran 600 s
  with the IEA 15 MW as a disk (kEqn RANS) and as a line (LES) on a build of
  2026-11-04. In two-level Askervein runs on a build of 2026-10-11, the anelastic
  projection with the FFT-preconditioned GMRES solver did not converge on the
  refined level (divergence 6e-5 to 2.4 there, against 1e-10 on level 0) and the
  temperature and kinetic energy grew on that level, ``mlmg`` stalled on the
  refined level, and a three-level actuator-line run blew up in its first step;
  a refined level also had to span the full height. The terrain projection has changed since: zero flux through
  Neumann faces (erf-model/ERF#4279), the ``mlmg`` and ``gmres_mlmg`` choices of
  ``erf.terrain_poisson_solver`` (#4280), refined levels that stop inside the
  domain in z (#4337), and the coarse/fine fluxes over terrain (#4879, #4902,
  #4925); and the coarser levels now carry the bodies' force. The same
  two-level Askervein case (60 coarse steps, Deardorff LES, refinement
  ``2 2 1``, the refined level spanning the full height of 18 cells) was rerun
  on a build of 2026-11-09 with each solver:

  ===========================  =============  ==============  =============
  Refined level, after step 1  ``gmres_fft``  ``gmres_mlmg``  ``mlmg``
  ===========================  =============  ==============  =============
  Largest divergence after     7e-10          3e-10           1e-8
  Temperature range (K)        299.95-300.05  299.95-300.05   299.95-300.05
  Wall time, 4 ranks (s)       116            201             127
  ===========================  =============  ==============  =============

  The first projection at start-up leaves 1.4e-5 on the refined level with
  every solver; the next solve brings it to 1e-10. The IEA 15 MW on the hill top
  as a disk and as a line (``gmres_mlmg``, 300 steps of 0.2 s) ran stably on the
  same build, with the temperature within 0.02 K of 300 K on both levels. These
  60 s runs cover only the controller's start-up, so they show stability, not
  performance. Three levels and a refined level that stops inside the domain
  in z were not rerun on Askervein; check the "divergence after" lines
  (``erf.mg_v = 1``) on every level of such a run.

Release notes
-------------

The ERF-MovingBodies branch (2026-10) adds: the moving-bodies framework
(velocity sampling and force spreading on uniform, stretched and
terrain-fitted meshes), the OpenFAST turbine driver with lockstep stepping,
restart and a start-up audit of the model and geometry, actuator disk and
actuator line modes with tower and nacelle forces, the filtered lifting-line
correction, upstream and corrected-disk sampling, prescribed-Ct disks,
multi-turbine farms whose turbines and disks are owned by ranks they stand on where the
balance allows and whose points (and wake lines) go only to the ranks they reach, wake lines and running
statistics, turbulent inflow from precursor planes or cell perturbations,
the anchor level on multi-level grids, bodies on terrain, the canonical
cases with golds, box-parity and restart-parity tests, the OpenFAST-stub CI
job, and two cases with the real OpenFAST library and the IEA 15 MW reference
turbine on the Askervein hill, with their own CI job.
