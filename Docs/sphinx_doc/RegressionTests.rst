Regression tests
================

GALE registers its CTest suite with ``-DERF_ENABLE_TESTS=ON`` (see :doc:`Building`).
The input decks are in ``Exec/CanonicalTests/MovingBodies``, one directory per case with its
gold logs; the gold plotfiles are in ``Tests/ERFGoldFiles``. Most tests run on the bundled
OpenFAST stub library (``ERF_ENABLE_OPENFAST=ON``, ``ERF_OPENFAST_USE_STUB=ON``,
``ERF_ENABLE_FFT=ON``, MPI, not Windows). ERF's own regression suite is not registered in a
GALE build.

Running
-------

.. code-block:: bash

   ctest --test-dir cmake-build/Tests -L moving-bodies    # the canonical cases and the start-up aborts
   ctest --test-dir cmake-build/Tests -L restart-parity -R "OpenFAST|MovingBodies"
   ctest --test-dir cmake-build/Tests -L box-parity -R "OpenFAST|Actuator"
   ctest --test-dir cmake-build/Tests -L openfast-real    # real OpenFAST build only
   ctest --test-dir cmake-build/Tests -L rosco            # real OpenFAST build with ROSCO
   .github/workflows/scripts/run_unit_tests.sh cmake-build/ERF/Tests/Unit/erf_unit_tests
   ctest --test-dir cmake-build -L parallel -R "Actuator|BodyExchange"   # on 1, 2 and 4 ranks

How the tests check results
---------------------------

The tables below name these checks instead of describing them again.

- **Gold**: the plotfile matches its gold in ``Tests/ERFGoldFiles``; the named logs match the
  gold logs beside the deck to ten significant digits unless stated otherwise.
- **Force identity**: in every row, the integrated momentum source
  (``moving_bodies/momentum_source.csv``) equals minus the bodies' load: the thrust in
  ``T1_erf.csv``, or ``load_x`` in ``moving_bodies/total_load.csv`` for towers, nacelles and
  farms. The spreading is normalised exactly, so this holds to roundoff.
- **Box parity**: the deck runs in one box and split unevenly in x and y; plotfiles and logs
  must agree.
- **Owner parity**: the deck runs in one box (the body on rank 0, the I/O rank) and in three
  20-cell boxes in x (``amr.max_grid_size_x = 24``, the body on rank 1); the plotfiles and
  every file the owner writes must agree.
- **Owners**: a ``MovingBodies_Owners_*`` test runs a deck for one step on two ranks and
  checks which rank owns each body.
- **Restart parity**: the deck runs straight to step 10, and again to a checkpoint at step 5
  and on to step 10 (``Tests/RunRestartParity.cmake``). The plotfiles must agree with zero
  tolerance and the logs to ten digits. The run that writes the checkpoint goes on to step 10
  (``OVERRUN``), so the restart must drop the log rows past the checkpoint. A restart on
  another rank count compares the plotfile to the default tolerances and the logs to 8 digits,
  as the FFT solution differs at roundoff between rank counts.
- **Abort**: the run, or the restart (``Tests/RunRestartAbort.cmake``), must stop with a
  message naming the input.

OpenFAST driver
---------------

One stub rotor of IEA 15 MW size (``mode = none``) is driven by a prescribed uniform velocity
for five steps of a uniform anelastic flow and adds no forcing.

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Test
     - Checks
   * - ``OpenFAST_DriverOnly``
     - Plotfile equals the same deck run without ``erf.moving_bodies``. With MPI (``Tests/RunOpenFASTADM.cmake``): ``T1_erf.csv`` gold to six digits, non-zero thrust in every row, no momentum source written.

Test location: `OpenFAST_DriverOnly <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_DriverOnly>`__

Actuator velocity sampling
--------------------------

An anelastic box with the linear shear ``u = 5 + 0.05 z``, ``v = 1 + 0.01 z`` is sampled at
the nodes of one stub rotor with its hub at 150 m. The sampler is exact for a linear field.

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Test
     - Checks
   * - ``Actuator_Sampling``
     - Gold ``T1_flow.csv``; ``u = 12.5``, ``v = 2.5``, ``w = 0`` at the hub and as the blade mean in every row (``Tests/RunActuatorSampling.cmake``).
   * - ``ActuatorSampling_BoxParity``
     - Box parity, flow files to eight digits.

Test location: `Actuator_Sampling <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/Actuator_Sampling>`__

Actuator disk force spreading
-----------------------------

A uniform 10 m/s anelastic flow runs for ten steps through a prescribed uniform-Ct disk
(radius 120 m, hub 150 m, ``Ct = 0.75``, ``epsilon = 2 dx``). It builds with
``ERF_ENABLE_MOVING_BODIES=ON`` in place of OpenFAST. The disk's owner rank alone samples the
flow for it and writes its log, statistics and wake lines.

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Test
     - Checks
   * - ``Actuator_UniformCtDisk``
     - Gold plotfile and ``D1_disk.csv``; the integrated source equals the disk's thrust in every row (``Tests/RunCtDisk.cmake``).
   * - ``ActuatorCtDisk_BoxParity``
     - Box parity, plotfiles and disk logs.
   * - ``MovingBodies_Owners_CtDisk``
     - With wake lines 2 and 4 diameters behind: disk on rank 1, sampled points on rank 1 only, kernels on both ranks, wake lines on rank 0 only.
   * - ``ActuatorCtDisk_OwnerParity``
     - Owner parity: plotfiles, disk log, statistics, both wake files and the momentum source.
   * - ``MovingBodies_CtDisk_Restart_OwnerRank1``
     - Restart parity on two ranks with the disk on rank 1; statistics and wake sums (three wake samples) come back from the checkpoint.
   * - ``MovingBodies_CtDisk_RestartOnOneRank``
     - The same checkpoint restarted on one rank, which reads rank 1's files.

Test location: `Actuator_UniformCtDisk <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/Actuator_UniformCtDisk>`__

Turbine table on a prescribed disk
----------------------------------

Two disks side by side in a uniform 10.25 m/s flow for ten steps: ``T1`` names the turbine table
``NREL_5MW_126`` and ``D1`` keeps a constant ``Ct = 0.75``, both of radius 63 m at hub 90 m.

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Test
     - Checks
   * - ``Actuator_TurbineCtDisk``
     - Both disk logs against their golds to ten significant digits, then ``check_turbine_disk.py`` reads the table itself and requires, in every row, T1's ``ct`` and ``power_curve`` to be the table's values at its free-stream speed and both thrusts to be :math:`\tfrac{1}{2}\rho C_T U^2 \pi R^2` (``Tests/RunTurbineCtDisk.cmake``). Needs Python 3.

Test location: `Actuator_TurbineCtDisk <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/Actuator_TurbineCtDisk>`__

OpenFAST rotor as an actuator disk
----------------------------------

A uniform 10 m/s flow runs for ten steps through one stub turbine in ``mode = adm``; its loads
are spread as rings about the hub axis (``num_points_t = 16``, ``epsilon = 2 dx``). Unless
stated otherwise each case checks Gold (plotfile, ``T1_flow.csv``) and the force identity
(``Tests/RunOpenFASTADM.cmake``).

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Test
     - Checks
   * - ``OpenFAST_ADM_Uniform``, ``OpenFASTADM_BoxParity``
     - ``sampling = disk``; box parity of plotfiles and flow logs.
   * - ``OpenFAST_ADM_MergedRings``
     - ``adm_spreading = rings`` vs ``merged_rings``: plotfiles agree to :math:`10^{-12}` relative and absolute; 20 rings vs 60 (``Tests/RunOptionParity.cmake``).
   * - ``MovingBodies_AdmSpreadingUnknown``
     - Abort on an unknown ``adm_spreading``.
   * - ``OpenFAST_ADM_Upstream``, ``OpenFASTADM_Upstream_BoxParity``
     - ``sampling = upstream``: velocities from one diameter ahead of the hub along the shaft; box parity.
   * - ``OpenFAST_ADM_UpstreamNacelle``
     - Adds a nacelle drag point; the owner samples the hub as one more point. Gold plotfile and nacelle column of ``T1_erf.csv``; force identity with the nacelle drag.
   * - ``OpenFAST_ADM_DiskCorrected``
     - ``sampling = disk_corrected`` (filtered-disk factor of Shapiro, Gayme and Meneveau (2019), one-cell kernel, log ``T1_correction.csv``); box parity in ``OpenFASTADM_DiskCorrected_BoxParity``. Golds hold the relaxed update.
   * - ``OpenFAST_ADM_DiskCorrected_Restart``
     - Restart parity with the turbine on rank 1; the recovered free stream is restored.
   * - ``OpenFAST_ADM_DiskCorrected_OldUpdate``
     - ``correction_relax = 1`` reproduces the unrelaxed-update gold to 1e-8.
   * - ``OpenFAST_ADM_Terrain``
     - 100 m Witch-of-Agnesi ridge, turbine on top, ``base_pos`` z = 0. Gold ``moving_bodies/ground.csv`` (terrain height exactly 100 m); force identity (``fx == -thrust_x``) on the fitted mesh; ``OpenFASTADM_Terrain_BoxParity`` splits the ridge between boxes.
   * - ``OpenFAST_ALM_Terrain_VerifyTipCells``
     - Actuator line on the ridge with and without ``erf.moving_bodies.verify_tip_cells``: plotfiles identical.

Test location: `OpenFAST_ADM_Uniform <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Uniform>`__, `OpenFAST_ADM_Upstream <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Upstream>`__, `OpenFAST_ADM_UpstreamNacelle <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_UpstreamNacelle>`__, `OpenFAST_ADM_DiskCorrected <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_DiskCorrected>`__, `OpenFAST_ADM_Terrain <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Terrain>`__

OpenFAST rotor as an actuator line
----------------------------------

The disk deck runs with ``mode = alm`` and ``fllc = false``: loads are spread from 20 nodes
per blade (``epsilon = 2 dx``) that turn through the 50 m cells at 0.9 cells per step, under
the one-cell limit ``erf.moving_bodies.alm_max_tip_cells``. Unless stated otherwise each case
checks Gold and the force identity on the full force vector.

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Test
     - Checks
   * - ``OpenFAST_ALM_Uniform``, ``OpenFASTALM_BoxParity``
     - Gold, force identity; box parity as blade points cross box faces.
   * - ``OpenFAST_ALM_Tower``
     - Tower (8 m, ``Cd`` 1, 10 force nodes, 6 sampled nodes) and nacelle (``Cd`` 1, 60 m^2); force identity on ``load_x``. ``OpenFASTALM_Tower_BoxParity`` puts the tower axis on a box face.
   * - ``OpenFAST_ALM_ComponentWidths``
     - Widths per kind: ``epsilon`` 1 cell, ``epsilon_tower`` 2, ``epsilon_nacelle`` 1.5; force identity on ``load_x``. The gtest ``OpenFASTRotor.TurbinePointsCarryTheWidthOfTheirKind`` checks which point gets which width.
   * - ``OpenFAST_ALM_Tower_ExplicitWidths``
     - ``OpenFAST_ALM_Tower`` with and without the two widths given equal to ``epsilon``: plotfiles identical (zero tolerance).
   * - ``OpenFASTALM_ComponentWidths_BoxParity``, ``OpenFAST_ALM_ComponentWidths_Restart``
     - Box parity with the tower axis on a box face; restart parity from step 5.
   * - ``MovingBodies_Restart_ChangedTowerWidth``
     - Abort on a restart with another ``epsilon_tower``.
   * - ``OpenFAST_ALM_FLLC``
     - Filtered lifting-line correction (chord 6 m: optimal kernel 1.5 m vs the run's 100 m). Gold plotfile and ``T1_fllc.csv``; force identity.
   * - ``OpenFAST_ALM_FLLC_Restart``
     - Restart parity with the turbine on rank 1, which writes and reads the correction and node-load checkpoint files.
   * - ``OpenFAST_ALM_FLLC_Automatic``
     - 20 steps with ``fllc = automatic`` vs ``fllc = true`` and the same values by hand (``fllc_eps_chord`` 0.15, ``fllc_eps_dr`` 3, ``fllc_start_time`` 5 s, 300 points per blade): plotfiles identical.
   * - ``OpenFAST_ALM_FLLC_Automatic_Restart``
     - Checkpoint at step 12 on two ranks (turbine on rank 1), restart to step 20: equals the straight run.
   * - ``MovingBodies_Restart_FllcAutomaticToTrue``
     - Abort on a restart with the automatic values given by hand.
   * - ``MovingBodies_FllcAutomaticWithEpsilon``
     - Abort when ``epsilon`` is given with ``fllc = automatic``.

Test location: `OpenFAST_ALM_Uniform <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_Uniform>`__, `OpenFAST_ALM_Tower <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_Tower>`__, `OpenFAST_ALM_ComponentWidths <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_ComponentWidths>`__, `OpenFAST_ALM_FLLC <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_FLLC>`__, `OpenFAST_ALM_FLLC_Restart <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_FLLC_Restart>`__, `OpenFAST_ALM_FLLC_Automatic <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_FLLC_Automatic>`__

Anchor level on two levels
--------------------------

The disk deck adds a level 1 of 25 m cells around the rotor and its near wake. The turbine is
sampled and forced on level 1; level 0 carries level 1's source restricted onto its faces
(`ERF's coarse-level source <https://erf.readthedocs.io/en/latest/theory/StructureCoupling.html#sec-structurecoarsesource>`__).

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Test
     - Checks
   * - ``OpenFAST_ADM_TwoLevel``, ``OpenFASTADM_TwoLevel_BoxParity``
     - Gold, force identity; box parity with the fine level split unevenly over two ranks.
   * - ``OpenFAST_ADM_TwoLevel_Restart``
     - Restart parity; fine level and turbine restored exactly.
   * - ``OpenFAST_ADM_TwoLevel_RestartLegacy``
     - Restart from a checkpoint rewritten by ``make_legacy_checkpoint.py`` to the earlier layout (``moving_bodies/force_x``, ``_y``, ``_z``): step 10 within relative 1e-10.
   * - ``OpenFAST_ADM_TwoLevel_RestartBodiesDir``
     - ``StructureCoarseSource`` moved to ``moving_bodies/``, its place before structure model ``gale``: step 10 matches exactly.
   * - ``MovingBodies_OneWayAboveLevel0``
     - Abort when bodies live above level 0 and ``erf.coupling_type`` is not ``TwoWay``.

Test location: `OpenFAST_ADM_TwoLevel <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoLevel>`__, `OpenFAST_ADM_TwoLevel_Restart <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoLevel_Restart>`__

Force on the levels below the anchor
------------------------------------

A prescribed-Ct disk (R = 120 m, Ct = 0.75, 10 m/s) runs on one level of 25 m cells and on a
level 1 of 12.5 m cells whose box ends 0.8 R up and down stream; the kernel is 25 m wide in
both.

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Test
     - Checks
   * - ``Actuator_CtDisk_TwoLevel``
     - After 60 s, the deficits of the disk-averaged velocity and of the velocity a quarter diameter upstream are within 10 % of the one-level run. Without the coarse-level force they were 44 % and 81 % smaller and the thrust 12 % larger.

Test location: `Actuator_CtDisk_TwoLevel <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/Actuator_CtDisk_TwoLevel>`__

Farms
-----

Two stub turbines run as disks, the second two diameters behind the first, each with its own
OpenFAST instance on its owner rank.

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Test
     - Checks
   * - ``OpenFAST_ADM_TwoTurbines``
     - Gold plotfile and ``T2_flow.csv``; force identity on the farm's ``load_x``.
   * - ``OpenFASTADM_TwoTurbines_BoxParity``
     - One rank vs three 20-cell boxes on two ranks (T2 on rank 1): plotfiles, T2's flow, turbine, statistics and correction logs, and ``total_load.csv`` agree.
   * - ``MovingBodies_Owners_TwoTurbines``, ``MovingBodies_Owners_FLLC``, ``MovingBodies_Owners_DiskCorrected``
     - Owners: with three 20-cell boxes, rank 1 owns the first turbine.
   * - ``MovingBodies_Owners_BoxParity``, ``MovingBodies_Owners_Balanced``
     - Owners: rank 1 owns the second turbine with the box-parity split, and with two 30-cell boxes where both bases are on rank 0's box.
   * - ``MovingBodies_MixedTimeSteps_TwoRanks``
     - Third turbine; the second steps with ``dt = 0.02`` instead of 0.01 and gets a rank of its own, the third joins the first. The run proceeds.
   * - ``MovingBodies_MixedTimeSteps_OneRank``
     - Abort naming the two substep counts.
   * - ``MovingBodies_Logs_OneOpenFile``
     - ``erf.moving_bodies.max_open_logs = 1`` on one rank: every log, statistics file and farm total holds the bytes of the run with no limit; ``MovingBodies_Logs_OneOpenFile_PerRank`` does the same with rank files on two ranks.
   * - ``MovingBodies_StatsInt_EndOfRun``, ``MovingBodies_StatsInt_EndOfRun_Farm``, ``MovingBodies_StatsInt_Wake``
     - ``stats_int`` of 4 steps in a 10-step run: statistics (or wake averages) equal those rewritten every step.
   * - ``MovingBodies_StatsInt_OneOpenFile_Restart``
     - Restart from step 5 with ``stats_int = 3`` and one open file: the straight run's logs and statistics.
   * - ``MovingBodies_StatsInt_RestartAtTheEnd``
     - Restart from step 5 with no step left: statistics rewritten from the checkpoint.
   * - ``MovingBodies_StatsInt_Farm_RestartAtTheEnd_OwnerRank1``
     - The same for the farm file with the turbine on rank 1 and rank 0 owning none: the collective rewrite holds the straight run's bytes.
   * - ``OpenFAST_ADM_TwoWidths``
     - One width per turbine (T1 2 cells, T2 1 cell); Gold, force identity and a box-parity twin.
   * - ``OpenFAST_ADM_DiskAndTurbine``
     - A prescribed-Ct disk (1 cell) where T2 stood: Gold plotfile and ``D2_disk.csv``; force identity on both bodies.
   * - ``OpenFASTADM_DiskAndTurbine_OwnerParity``, ``MovingBodies_Owners_DiskAndTurbine``
     - Disk upstream; owner parity with the disk on rank 1: plotfiles, disk log and statistics, turbine log and ``total_load.csv``.

Test location: `OpenFAST_ADM_TwoTurbines <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoTurbines>`__, `OpenFAST_ADM_TwoWidths <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoWidths>`__, `OpenFAST_ADM_DiskAndTurbine <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_DiskAndTurbine>`__

Real OpenFAST on terrain
------------------------

These cases need ``-DERF_ENABLE_OPENFAST=ON -DERF_OPENFAST_USE_STUB=OFF`` with OpenFAST 5,
FFT and MPI (label ``openfast-real``). The IEA 15 MW reference turbine
(``Exec/CanonicalTests/MovingBodies/IEA15_land_model``) stands 123 m up on the summit of the
Askervein hill, on a fitted mesh of 50 m cells with a uniform 10 m/s inflow, for ten steps of
0.4 s. The blades flap downwind once released (thrust drops by 60 %, torque by over 80 % in
the first step), so these are start-up regressions of the coupling, not validations.

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Test
     - Checks
   * - ``OpenFAST_ADM_Askervein``
     - Gold plotfile to 1e-6 relative; ``T1_flow.csv`` and ``T1_erf.csv`` to two units of the sixth digit. Source equals minus the shaft component of the thrust on x, ``(T . n) n_x``, to 1e-8 (``Tests/check_openfast_shaft_source.py``).
   * - ``OpenFAST_ALM_Askervein``
     - The same golds; force identity on ``load_x`` to 8 digits.
   * - ``MovingBodies_ShaftSourceChecker_pass``, ``MovingBodies_ShaftSourceChecker_mismatch``, ``MovingBodies_ShaftSourceChecker_plain_x``
     - The checker on fixed logs: the disk case's own must pass, one row off by 1e-6 must fail, a stub disk with loads along x must be refused.

The golds are per platform: ``Tests/ERFGoldFiles/OpenFAST_{ADM,ALM}_Askervein_macOS`` and
``..._Linux``, and ``T1_erf.csv.macOS.gold`` and ``T1_erf.csv.Linux.gold`` (likewise
``T1_flow.csv``) beside the deck. macOS arm64 and the ``Linux GCC OpenFAST 5`` CI job agree
exactly for four steps, then part: the feedback in both corrections amplifies a last-bit libm
difference to 4e-5 relative in the velocities, 1e-3 in the thrust and 4e-3 in the power by
step ten. One shared gold set would need tolerances coarser than the changes these cases
exist to catch. Within one platform the answers are reproducible; one and two ranks agree to
1e-15.

Test location: `OpenFAST_ADM_Askervein <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Askervein>`__, `OpenFAST_ALM_Askervein <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_Askervein>`__

Wake sampling lines
-------------------

The disk case samples wake lines 2, 4 and 7 diameters behind the rotor (41 points over
±1.5 D, lateral and vertical) every two steps and averages them from 2 s on.

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Test
     - Checks
   * - ``OpenFAST_ADM_Wake``, ``OpenFASTADM_Wake_BoxParity``
     - Gold plotfile and ``T1_wake_avg.csv``; box parity of ``T1_wake.csv`` to eight digits.

Test location: `OpenFAST_ADM_Wake <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Wake>`__

Turbulent inflow from a precursor
---------------------------------

The stub disk runs for ten steps in a turbulent inflow.

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Test
     - Checks
   * - ``OpenFAST_ADM_LES``
     - Inflow from the boundary planes of a 14-step periodic Smagorinsky precursor (``Tests/RunPrecursorInflow.cmake``): Gold plotfile and ``T1_stats.csv``; force identity.
   * - ``OpenFAST_ADM_CPM``
     - Steady 10 m/s inflow with ``erf.perturbation_type = CPM``: the same checks.

Test location: `OpenFAST_ADM_LES <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_LES>`__, `OpenFAST_ADM_CPM <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_CPM>`__

OpenFAST turbine restart
------------------------

The disk case runs with two wake lines; the turbine restarts from its OpenFAST checkpoint
under ``chk00005/moving_bodies``.

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Test
     - Checks
   * - ``OpenFAST_ADM_Restart``
     - Restart parity: wake average, correction, turbine, flow and statistics logs, momentum source and total load.
   * - ``MovingBodies_Restart_ChangedBodyKey``, ``MovingBodies_Restart_ChangedAdmSpreading``, ``MovingBodies_Restart_ChangedStep``, ``MovingBodies_Restart_LaterStopTime``, ``MovingBodies_Restart_AddedBody``
     - Abort on, in order: a changed ``num_points_t``, ``adm_spreading`` or ``erf.fixed_dt``; a stop time past the one OpenFAST was started with; a second body.
   * - ``MovingBodies_Restart_MalformedStatsOnRank1``, ``MovingBodies_Restart_MalformedWakeOnRank1``
     - Turbine on rank 1; a malformed statistics or wake-average file stops every rank with that file's message (a hang would hit the 180 s limit).
   * - ``MovingBodies_CtDisk_Restart``
     - Restart parity for the prescribed-Ct disk, with a later stop time on restart.
   * - ``MovingBodies_Restart_ChangedDiskDensity``
     - Abort on a changed ``air_density``.
   * - ``OpenFAST_ADM_Restart_WakeOwnerRank1``, ``MovingBodies_Owners_Wake``
     - Restart parity on two ranks with the turbine and its wake lines on rank 1.
   * - ``OpenFAST_ADM_TwoTurbines_Restart``
     - The farm on two ranks; rank 1 writes and trims T1's logs and checkpoint files.
   * - ``OpenFAST_ADM_TwoTurbines_RestartOnOneRank``
     - Checkpoint on two ranks, restart on one, which reads rank 1's files.
   * - ``MovingBodies_DiagnosticsFormat_PerRank_RestartOnOneRank``
     - Per-rank logs on two ranks, restart on one with no step left: the I/O rank cuts rank 1's files back to a 5-step run's bytes (``Tests/RunTrimOnRestart.cmake``).
   * - ``MovingBodies_Restart_OwnersCutTheirLogs``
     - One file per body on two ranks: each owner cuts its turbine's files once (rank 1 for T1, rank 0 for T2); the I/O rank cuts the farm totals.
   * - ``MovingBodies_Restart_WakeOwnerCutsItsLog``
     - The wake file of a turbine on rank 1 is cut by its owner.

Test location: `OpenFAST_ADM_Restart <https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Restart>`__
