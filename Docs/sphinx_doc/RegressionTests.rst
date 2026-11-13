Regression tests
================

GALE's CTest suite, registered with ``-DERF_ENABLE_TESTS=ON`` (see :doc:`Building`). Gold files
are in ``Tests/ERFGoldFiles``; the input decks are in ``Exec/CanonicalTests/MovingBodies``.
ERF's own regression suite is not registered in a GALE build.

OpenFAST driver
---------------
``OpenFAST_DriverOnly`` (``mode = none``; builds with ``ERF_ENABLE_OPENFAST=ON``,
``ERF_OPENFAST_USE_STUB=ON`` and ``ERF_ENABLE_FFT=ON``) steps one moving body
(:ref:`sec:MovingBodiesInputs`) through five steps of a uniform anelastic flow.
The body is an IEA-15-MW-sized rotor of the bundled OpenFAST stub library,
driven by a prescribed uniform velocity and adding no forcing to the flow, so
the plotfile must equal the gold file, which is the same deck run without the
``erf.moving_bodies`` block. Since that holds even if the turbine never ran,
with MPI ``Tests/RunOpenFASTADM.cmake`` also compares the turbine's diagnostics
file ``T1_erf.csv`` with its gold (time, rotor speed, axial thrust, torque,
power and hub axis to six digits, the precision OpenFAST hands its loads back
in), requires a non-zero thrust in every row and requires that no momentum
source was written.

Test Location: `Exec/CanonicalTests/MovingBodies/OpenFAST_DriverOnly`_

.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_DriverOnly`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_DriverOnly

Actuator velocity sampling
--------------------------
``Actuator_Sampling`` (builds with ``ERF_ENABLE_OPENFAST=ON``,
``ERF_OPENFAST_USE_STUB=ON``, ``ERF_ENABLE_FFT=ON`` and MPI, not Windows) starts
an anelastic box from a sounding with the linear shear ``u = 5 + 0.05 z``,
``v = 1 + 0.01 z`` and samples the flow at the nodes of one stub OpenFAST rotor
(hub at 150 m). The sampler is exact for a linear field, so the turbine's
flow file ``T1_flow.csv`` must match its gold log to ten significant digits
and, in every row, show ``u = 12.5``, ``v = 2.5`` and ``w = 0`` at the hub and
as the blade mean (``Tests/RunActuatorSampling.cmake``).
``ActuatorSampling_BoxParity`` runs the same deck with the domain in one box and
split unevenly in x and y and requires the flow files to agree to eight
significant digits.

Test Location: `Exec/CanonicalTests/MovingBodies/Actuator_Sampling`_

.. _`Exec/CanonicalTests/MovingBodies/Actuator_Sampling`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/Actuator_Sampling

Actuator disk force spreading
-----------------------------
``Actuator_UniformCtDisk`` (builds with ``ERF_ENABLE_MOVING_BODIES=ON``,
``ERF_ENABLE_FFT=ON`` and MPI, not Windows) runs a uniform 10 m/s anelastic
flow for ten steps through a prescribed uniform-Ct disk (radius 120 m, hub
150 m, ``Ct = 0.75``, ``epsilon = 2 dx``). ``Tests/RunCtDisk.cmake`` compares
the plotfile with its gold, the disk's log ``D1_disk.csv`` with its gold to ten
significant digits, and requires in every row that the integrated momentum
source equals the disk's thrust, since the spreading is normalised exactly.
``ActuatorCtDisk_BoxParity`` runs the same deck in one box and split unevenly
in x and y and requires the plotfiles and the disk logs to agree.

The disk has an owner rank, which alone samples the flow for it and writes its
log, statistics and wake lines. ``MovingBodies_Owners_CtDisk`` runs the deck
with wake lines 2 and 4 diameters behind the disk for one step on two ranks
with three 20-cell boxes in x (``amr.max_grid_size_x = 24``) and requires the
disk to be owned by rank 1, its sampled points to reach rank 1 alone, its
kernels both ranks, and its wake lines rank 0 alone (they lie on rank 0's boxes,
so rank 1 samples them through rank 0). ``ActuatorCtDisk_OwnerParity``
runs that deck in one box (the disk on rank 0, the I/O rank) and in the
three-box layout (the disk on rank 1) and requires the plotfiles, every file
the owner writes (the disk log, statistics and both wake files) and the momentum
source the I/O rank writes to agree. ``MovingBodies_CtDisk_Restart_OwnerRank1`` checkpoints the
three-box run at step 5 and restarts it to step 10 on two ranks (with
``OVERRUN``): the logs rank 1 wrote past the checkpoint must be dropped, and
the statistics and wake sums it wrote into the checkpoint taken over (the lines
are sampled every step and averaged from 1 s, so the checkpoint holds three
wake samples). ``MovingBodies_CtDisk_RestartOnOneRank`` restarts the same
checkpoint on one rank, which then owns the disk and reads what rank 1 wrote
(plotfile to the default tolerances, logs to 8 digits, as the FFT solution
differs at roundoff between rank counts).

Test Location: `Exec/CanonicalTests/MovingBodies/Actuator_UniformCtDisk`_

.. _`Exec/CanonicalTests/MovingBodies/Actuator_UniformCtDisk`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/Actuator_UniformCtDisk

OpenFAST rotor as an actuator disk
----------------------------------
The moving-bodies cases live in ``Exec/CanonicalTests/MovingBodies``, one
directory per case with its deck, the stub turbine file and its gold logs (the
gold plotfiles stay in ``Tests/ERFGoldFiles``); the README there lists them.
``OpenFAST_ADM_Uniform`` (builds with ``ERF_ENABLE_OPENFAST=ON``,
``ERF_OPENFAST_USE_STUB=ON``, ``ERF_ENABLE_FFT=ON`` and MPI, not Windows) runs a
uniform 10 m/s anelastic flow for ten steps through one stub OpenFAST turbine
in ``mode = adm`` with ``sampling = disk``: the stub's loads, from the velocities sampled at its nodes,
are spread as rings about the hub axis (``num_points_t = 16``,
``epsilon = 2 dx``) and slow the flow. ``Tests/RunOpenFASTADM.cmake`` compares
the plotfile with its gold, the sampled flow log ``T1_flow.csv`` with its gold
to ten significant digits, and requires in every row that the integrated
momentum source in ``moving_bodies/momentum_source.csv`` equals minus the
thrust in ``T1_erf.csv``, since the rings preserve the rotor force and the
spreading is normalised exactly. ``OpenFASTADM_BoxParity`` runs the same deck
in one box and split unevenly in x and y and requires the plotfiles and the
flow logs to agree. ``OpenFAST_ADM_MergedRings`` (``Tests/RunOptionParity.cmake``)
runs the same deck with ``adm_spreading = rings`` and ``merged_rings``. The stub
rotor is rigid, so the plotfiles must agree to a relative and absolute
tolerance of :math:`10^{-12}` (the forces are summed in another order), and the
second run's log must count 20 rings, one per radial station, where the first builds 60. ``MovingBodies_AdmSpreadingUnknown``
gives the key an unknown value and requires the run to stop naming it.

Test Location: `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Uniform`_

.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Uniform`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Uniform

``OpenFAST_ADM_Upstream`` runs the same deck with ``sampling = upstream``: the
velocities handed to the stub come from one diameter ahead of the hub along the
shaft axis instead of from the disk, so the free stream and not the resolved
induction sets the loads (with OpenFAST this mode requires ``Wake_Mod = 1``).
The shifted sampling points are covered like the nodes; the rings and the
spreading are unchanged, so the same three checks apply, and
``OpenFASTADM_Upstream_BoxParity`` is its one-box-versus-split twin.
``OpenFAST_ADM_UpstreamNacelle`` adds a nacelle drag point, whose drag needs the
velocity at the hub rather than ahead of it: the turbine's owner samples the hub
as one more point. The plotfile and the nacelle column of ``T1_erf.csv`` match
golds made by the code that sampled the hub separately on every rank, and the
integrated source equals minus the load with the nacelle's drag.

Test Location: `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Upstream`_ and `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_UpstreamNacelle`_

.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Upstream`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Upstream
.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_UpstreamNacelle`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_UpstreamNacelle

``OpenFAST_ADM_DiskCorrected`` runs the same deck with ``sampling = disk_corrected``:
the velocities are sampled at the disk, and the free stream handed to the stub is
recovered from the radius-weighted axial disk velocity with the filtered-disk
factor of Shapiro, Gayme and Meneveau (2019) and momentum theory on the previous
step's thrust, logged in ``T1_correction.csv`` (with OpenFAST this mode requires
``Wake_Mod = 1``); the kernel is one cell wide so the filter width stays within
the range the factor was derived for. The same three checks apply;
``OpenFASTADM_DiskCorrected_BoxParity`` is the one-box-versus-split twin, and
``OpenFAST_ADM_DiskCorrected_Restart`` runs it straight to step 10 and again
through a checkpoint at step 5, requiring the plotfiles and every log to agree:
the recovered free stream is part of the moving-bodies checkpoint. Its boxes are
20 cells long in x (``amr.max_grid_size_x = 24``), so the turbine is owned by
rank 1 and the free stream reaches
the checkpoint's state file, which the I/O rank writes, from another rank. Since the
relaxation of the update became the default, this deck's golds (and those of
the other decks that run ``disk_corrected``) hold the relaxed update;
``OpenFAST_ADM_DiskCorrected_OldUpdate`` runs the deck with
``correction_relax = 1`` and must reproduce the gold of the unrelaxed update to
1e-8.

Test Location: `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_DiskCorrected`_

.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_DiskCorrected`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_DiskCorrected

``OpenFAST_ADM_Terrain`` runs the uniform-inflow disk on a terrain-fitted mesh:
a 100 m Witch-of-Agnesi ridge across the flow with the stub turbine on its top
and ``base_pos`` z = 0, which on a fitted mesh is the terrain surface there. The
log compared with its gold is ``moving_bodies/ground.csv`` (body, x, y, terrain
height, base z); the ridge top is a mesh node, so the recorded height is exactly
100 m. The plotfile gold and the ``fx == -thrust_x`` check exercise the sampler
and the spreader in the fitted mesh's physical heights and cell volumes.
``OpenFASTADM_Terrain_BoxParity`` splits the ridge between boxes.
``OpenFAST_ALM_Terrain_VerifyTipCells`` runs the deck as an actuator line (the
tip limit raised over the 1.11 physical cells it sweeps per step) with and
without ``erf.moving_bodies.verify_tip_cells``, which checks the cached tip cell
heights against the per-region search every step; the plotfiles must be identical.

Test Location: `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Terrain`_

.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Terrain`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Terrain

OpenFAST rotor as an actuator line
----------------------------------
``OpenFAST_ALM_Uniform`` (same build requirements) runs the actuator-disk deck
with ``mode = alm`` and ``fllc = false`` (the plain line): the stub's loads are spread from its rotating blade nodes
(20 per blade, ``epsilon = 2 dx``) instead of as rings, so the three lines of
force turn through the 50 m cells at 0.9 cells per step, under the one-cell
limit ``erf.moving_bodies.alm_max_tip_cells`` (a 1 s step aborts at the first
step). The same three checks apply: plotfile and ``T1_flow.csv`` against their
golds, and the integrated momentum source equal to minus the thrust in every
row, which for the line holds for the full force vector.
``OpenFASTALM_BoxParity`` runs the deck in one box and split unevenly in x and
y: the blade points cross box faces as they turn, so the plotfiles and flow logs
must agree. ``OpenFAST_ALM_Tower`` adds the tower and the nacelle: the stub
puts a cylinder drag (8 m, ``Cd`` 1) on 10 tower force nodes from the
velocities sampled at its 6 tower nodes, and ERF adds a nacelle drag point
(``Cd`` 1, 60 m^2) at the hub; the integrated momentum source must equal
minus the total load ``load_x`` (thrust plus tower plus nacelle) in every
row, and the plotfile with the tower wake matches its gold;
``OpenFASTALM_Tower_BoxParity`` splits the domain so that the tower axis falls
on a box face and requires the plotfiles and flow logs to agree with the
one-box run.

``OpenFAST_ALM_ComponentWidths`` is that deck with a kernel width for each kind
of point: the blade and hub nodes 1 cell (``epsilon``), the tower force nodes
2 cells (``epsilon_tower``) and the nacelle drag point 1.5 cells
(``epsilon_nacelle``). The plotfile and ``T1_flow.csv`` match their golds and
the integrated source still equals minus ``load_x``, which holds whatever the
widths are; which point gets which width is checked by the gtest
``OpenFASTRotor.TurbinePointsCarryTheWidthOfTheirKind``.
``OpenFAST_ALM_Tower_ExplicitWidths`` runs ``OpenFAST_ALM_Tower`` with and
without ``epsilon_tower`` and ``epsilon_nacelle`` given equal to ``epsilon``
and requires the two plotfiles to be identical (zero tolerance, one machine):
widths that are not given are ``epsilon``, and ``OpenFAST_ALM_Tower``'s own
gold then holds the shared width to its answers.
``OpenFASTALM_ComponentWidths_BoxParity`` puts the tower axis on
a box face, ``OpenFAST_ALM_ComponentWidths_Restart`` restarts it from step 5
exactly, and ``MovingBodies_Restart_ChangedTowerWidth`` requires a restart
with another ``epsilon_tower`` to stop, naming it.

``OpenFAST_ALM_FLLC`` runs the actuator-line deck with the filtered
lifting-line correction on (the stub reports a chord of 6 m, so the optimal
kernel is 1.5 m against the run's 100 m): the correction log
``T1_fllc.csv`` and the plotfile must match their golds, and the integrated
source still equals minus the thrust in every row (the correction changes the
velocities the blades see, not the force identity).
``OpenFAST_ALM_FLLC_Restart`` checkpoints that case at step 5 and restarts to
step 10: the relaxed correction comes back from the checkpoint, so the
plotfile and the correction log must equal the straight run's exactly. With
three 20-cell boxes in x (``amr.max_grid_size_x = 24``) the turbine is owned by
rank 1, which writes the correction's and
the node loads' checkpoint files and reads them back.
``OpenFAST_ALM_FLLC_Automatic`` runs the same line for 20 steps with
``fllc = automatic`` and again with ``fllc = true`` and the values automatic
sets given by hand (``epsilon`` at the value it prints, ``fllc_eps_chord`` 0.15,
``fllc_eps_dr`` 3, ``fllc_start_time`` 5 s, 300 points per blade): the plotfiles
must be identical, so automatic only sets inputs, and the correction acts on the
last 10 steps. ``OpenFAST_ALM_FLLC_Automatic_Restart`` checkpoints it at step 12
on two ranks, the turbine owned by rank 1, and restarts to step 20: the width is
set again from the restored rotor and the run must equal the straight one.
``MovingBodies_Restart_FllcAutomaticToTrue`` restarts it with the same numbers
given by hand, which must abort, and ``MovingBodies_FllcAutomaticWithEpsilon``
gives ``epsilon`` with automatic, which must abort naming the key.

Test Location: `Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_Uniform`_, `Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_Tower`_, `Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_ComponentWidths`_, `Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_FLLC`_, `Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_FLLC_Restart`_ and `Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_FLLC_Automatic`_

.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_Uniform`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_Uniform
.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_Tower`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_Tower
.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_ComponentWidths`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_ComponentWidths
.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_FLLC`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_FLLC
.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_FLLC_Restart`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_FLLC_Restart
.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_FLLC_Automatic`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_FLLC_Automatic

Anchor level on two levels
--------------------------
``OpenFAST_ADM_TwoLevel`` (same build requirements) runs the actuator-disk
deck with a level 1 of 25 m cells over a box around the rotor and its near
wake: the turbine lives on level 1 (the default anchor), is sampled and forced
there with the fine level's step, and level 0 carries level 1's momentum
source restricted onto its faces (`ERF's coarse-level source <https://erf.readthedocs.io/en/latest/theory/StructureCoupling.html#sec-structurecoarsesource>`__). The
two-level plotfile and ``T1_flow.csv`` match their golds and
the integrated source equals minus the thrust in every row.
``OpenFASTADM_TwoLevel_BoxParity`` splits the fine level unevenly over two
ranks and requires the plotfiles and the flow log to agree, and
``OpenFAST_ADM_TwoLevel_Restart`` checkpoints at step 5 and restarts to step
10 with the fine level and the turbine restored exactly.
``OpenFAST_ADM_TwoLevel_RestartLegacy`` rewrites the step-5 checkpoint with
``make_legacy_checkpoint.py`` into the layout of an earlier version (the
anchor level's face forces in ``moving_bodies/force_x``, ``_y``, ``_z``),
restarts from it and requires step 10 to match the straight run to a relative
1e-10 (on this uniform-dz mesh, where the face Jacobian is 1).
``OpenFAST_ADM_TwoLevel_RestartBodiesDir`` moves the step-5 checkpoint's
``StructureCoarseSource`` into ``moving_bodies/``, where the bodies wrote it before
they became structure model ``gale``, and requires step 10 of the restart to match
the straight run exactly. ``MovingBodies_OneWayAboveLevel0`` requires the run to abort when the
bodies live above level 0 and ``erf.coupling_type`` is not ``TwoWay``.

Test Location: `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoLevel`_ and `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoLevel_Restart`_

.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoLevel`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoLevel
.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoLevel_Restart`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoLevel_Restart

Force on the levels below the anchor
------------------------------------
``Actuator_CtDisk_TwoLevel`` runs a prescribed-Ct disk (R = 120 m, Ct = 0.75,
10 m/s) on one level of 25 m cells and again on two, with the disk on a level 1
of 12.5 m cells whose box ends 0.8 R up and down stream of it, the kernel 25 m
wide in both. The coarse level carries the disk's force summed onto its faces
from level 1, so after 60 s the velocity deficits of the disk-averaged velocity
and of the velocity a quarter of a diameter upstream agree with the one-level
run's within 10 %. Without the coarse-level force the deficits were 44 % and
81 % smaller and the thrust 12 % larger.

Test Location: `Exec/CanonicalTests/MovingBodies/Actuator_CtDisk_TwoLevel`_

.. _`Exec/CanonicalTests/MovingBodies/Actuator_CtDisk_TwoLevel`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/Actuator_CtDisk_TwoLevel

Farms
-----
``OpenFAST_ADM_TwoTurbines`` (same build requirements) runs two stub turbines
as actuator disks, the second two diameters downstream of the first: each has
its own OpenFAST instance on its owner rank and its own logs, and the
integrated momentum source must equal minus the farm's total load
(``load_x`` in ``moving_bodies/total_load.csv``) in every row; the downstream
turbine's sampled flow log ``T2_flow.csv`` and the plotfile are the golds.
``OpenFASTADM_TwoTurbines_BoxParity`` runs the farm on one rank (both turbines
on rank 0) against two ranks with the domain cut into three 20-cell boxes in x
(``amr.max_grid_size_x = 24``; the first turbine on rank 0, the second on
rank 1) and requires the plotfiles and the
second turbine's flow, turbine, statistics and correction logs, and the farm's
``total_load.csv``, to agree, so the ownership changes neither the answer nor
what the owners write and the I/O rank gathers.

Which rank owns which turbine is checked by ``MovingBodies_Owners_*``: each runs
a deck for one step on two ranks and requires it to end normally with the
owners the tests above rely on. With three 20-cell boxes in x
(``amr.max_grid_size_x = 24``) rank 1 owns the first turbine (``_TwoTurbines``,
``_FLLC``, ``_DiskCorrected``) and, with the box-parity test's split, the second
(``_BoxParity``); with the default two 30-cell boxes both bases stand on rank
0's box, and the second turbine still goes to rank 1, which owns none
(``_Balanced``), as dealing them out would.
``MovingBodies_MixedTimeSteps_TwoRanks`` adds a third turbine behind the two
and gives the second a model that steps with ``dt = 0.02`` instead of 0.01: on
two ranks the second gets a rank of its own and the third joins the first,
where balance alone would have put it with the second; the run proceeds. On
one rank (``MovingBodies_MixedTimeSteps_OneRank``) two time steps cannot be
kept apart and the run stops, naming the two substep counts.

How the logs are written must not change what they hold. ``MovingBodies_Logs_OneOpenFile``
runs the two-turbine farm on one rank with ``erf.moving_bodies.max_open_logs = 1``, so every
row closes another file and opens its own again to append, and requires every log, statistics
file and farm total to hold the bytes of the run with no limit; ``_PerRank`` does the same with
the rank files on two ranks. ``MovingBodies_StatsInt_EndOfRun`` (and ``_Farm``) rewrites the
statistics every 4 steps of the 10-step run (``stats_int``), so the last rewrite is the one at
the end of the run, and requires the files of the run that rewrites them at every step;
``MovingBodies_StatsInt_Wake`` does the same for the wake averages.
``MovingBodies_StatsInt_OneOpenFile_Restart`` restarts that farm from step 5 with
``stats_int = 3`` and one open file, after a first run that went on past the checkpoint, and
requires the straight run's logs and statistics. ``MovingBodies_StatsInt_RestartAtTheEnd``
restarts from step 5 with no step left, after a first run that went on to step 10: the
statistics files must be rewritten from the checkpoint's state. ``MovingBodies_StatsInt_Farm_RestartAtTheEnd_OwnerRank1``
does the same through the farm file, with the turbine owned by rank 1 and rank 0
owning none: the ranks must agree to rewrite the file, as that rewrite is
collective, and it must hold the straight run's bytes.

``OpenFAST_ADM_TwoWidths`` is that farm with a kernel width per turbine (T1
2 cells, T2 1 cell, which also sets T2's filtered-disk correction): the same
checks against its own golds and a box-parity twin.
``OpenFAST_ADM_DiskAndTurbine`` puts a prescribed-Ct disk spread over 1 cell
where T2 stood, behind the turbine spread over 2: the disk's log ``D2_disk.csv``
and the plotfile match their golds and the integrated source equals minus the
total load of both bodies. ``OpenFASTADM_DiskAndTurbine_OwnerParity`` swaps the
two (the disk upstream) and runs them in one box, where rank 0 owns both, and in
three 20-cell boxes in x, where the disk is owned by rank 1
(``MovingBodies_Owners_DiskAndTurbine``): the plotfiles, the disk's log and
statistics, the turbine's log and the farm's ``total_load.csv``, which the I/O
rank gathers from the disk's owner, must agree.

Test Location: `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoTurbines`_, `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoWidths`_ and `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_DiskAndTurbine`_

.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoTurbines`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoTurbines
.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoWidths`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_TwoWidths
.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_DiskAndTurbine`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_DiskAndTurbine

Real OpenFAST on terrain
------------------------
``OpenFAST_ADM_Askervein`` and ``OpenFAST_ALM_Askervein`` (needs
``-DERF_ENABLE_OPENFAST=ON -DERF_OPENFAST_USE_STUB=OFF`` with an OpenFAST 5
installation, FFT and MPI; label ``openfast-real``) run the real OpenFAST library
on the IEA 15 MW reference turbine (``Exec/CanonicalTests/MovingBodies/IEA15_land_model``,
from the IEA Wind Task 37 repository; its README lists every change) on the summit
of the Askervein hill (``Submodules/ERF/Exec/CanonicalTests/Real_Terrain/Askervein/askervein.txt``)
on a terrain-fitted mesh of 50 m cells: a uniform 10 m/s mass inflow 2.7 km
upstream, a pressure outflow 3.3 km downstream, slip walls elsewhere and no sponge,
ten steps of 0.4 s. The base is raised 123 m onto the hill and the start-up audit
compares the model's density with ERF's at the hub. Ten steps from a uniform flow
are a start-up (the blades flap downwind once released: the thrust drops by 60 %
and the torque by over 80 % in the first step, then recovers), so these are
regressions of the coupling, not validations.

The plotfile, ``T1_flow.csv`` and the turbine's rotor speed, loads, torque and
power in ``T1_erf.csv`` match golds at a relative tolerance of 1e-6 for the
plotfile and two units of the sixth significant digit for the logs. The golds are
per platform: ``Tests/ERFGoldFiles/OpenFAST_{ADM,ALM}_Askervein_macOS`` and
``..._Linux`` for the plotfiles, ``T1_erf.csv.macOS.gold`` and
``T1_erf.csv.Linux.gold`` (likewise ``T1_flow.csv``) beside the deck. macOS arm64
(Apple clang, Homebrew gfortran, Accelerate) and the ``Linux GCC OpenFAST 5`` CI
job both run OpenFAST 5.0.0 and agree exactly for the first four steps, then part:
the line's filtered lifting-line correction and the disk's correction feed their
own output back, so a last-bit difference in one of their filters, from a
different libm and Fortran compiler, grows over the ten steps to 4e-5 relative in
the velocities, 1e-3 in the thrust and 4e-3 in the power. One gold set would
therefore need about 1e-4 on the plotfile and 1e-2 on the power, coarser than the
changes these cases exist to catch, so each platform keeps its own set and is
refreshed on that platform. Within one platform the answers are reproducible:
OpenFAST's loads cross to ERF in single precision, so a load rounds at most 6e-8
relative (of order 1e-8 relative in the flow); one and two ranks agree to 1e-15.
The load check
is an identity. For the actuator line, with its tower and nacelle forced, the
integrated source equals minus the total load ``load_x`` (to 8 digits). For the
actuator disk, whose rings carry each blade node's force along the tilted (6
degree) shaft and in-plane parts that cancel around each ring, it equals minus the
shaft component of the thrust projected on x, ``(T . n) n_x``, to 1e-8
(``Tests/check_openfast_shaft_source.py``; OpenFAST sets the hub node's force to
zero). ``MovingBodies_ShaftSourceChecker_pass``, ``_mismatch`` and ``_plain_x``
run that checker on fixed logs: the disk case's own, the same with one row off
by 1e-6 (must fail), and a stub disk whose loads lie along x (must refuse, as the
check would then be the plain x identity). The ``Linux GCC OpenFAST 5`` CI job runs
the two cases.

Test Location: `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Askervein`_ and `Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_Askervein`_

.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Askervein`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Askervein
.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_Askervein`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ALM_Askervein

Wake sampling lines
-------------------
``OpenFAST_ADM_Wake`` (same build requirements) is the actuator-disk case with
wake lines 2, 4 and 7 diameters behind the rotor (41 points over ±1.5 D,
lateral and vertical), sampled every two steps and averaged from 2 s on. The
running average ``T1_wake_avg.csv`` must match its gold to ten significant
digits and the plotfile its gold. ``OpenFASTADM_Wake_BoxParity`` runs the deck
in one box and split unevenly and requires the instantaneous wake file
``T1_wake.csv`` to agree to eight digits.

Test Location: `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Wake`_

.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Wake`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Wake

Turbulent inflow from a precursor
---------------------------------
``OpenFAST_ADM_LES`` (same build requirements) first runs a periodic anelastic
Smagorinsky precursor of the actuator-disk box (perturbed uniform 10 m/s flow,
14 steps) that writes its boundary planes every step, then the stub rotor as a
disk in the same box for ten steps with inflow read from those planes, outflow
downstream and the anelastic FFT solve on the non-periodic direction
(``Tests/RunPrecursorInflow.cmake``). The plotfile and the turbine's running
statistics ``T1_stats.csv`` must match their golds and the integrated momentum
source must equal minus the thrust in every row.

``OpenFAST_ADM_CPM`` makes the turbulent inflow in one run instead, with a
steady 10 m/s inflow profile and ERF's cell perturbation method
(``erf.perturbation_type = CPM``) just inside the inflow face; the same three
checks apply.

Test Location: `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_LES`_ and `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_CPM`_

.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_LES`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_LES
.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_CPM`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_CPM

OpenFAST turbine restart
------------------------
``OpenFAST_ADM_Restart`` (same build requirements) runs the actuator-disk case
with two wake lines straight to step 10, then to a checkpoint at step 5 and
from that checkpoint to step 10 (``Tests/RunRestartParity.cmake``). The turbine
is restored from its OpenFAST checkpoint under ``chk00005/moving_bodies``, the
momentum source is rebuilt from the restored loads and the wake running
average continues from its checkpointed sums, so the restarted run's plotfile
must equal the straight run's with zero tolerance and its logs (the wake
average, the correction, the turbine, flow and statistics logs, the momentum
source and the total load) must match to ten significant digits. The run that
writes the checkpoint goes on to step 10 (``OVERRUN``), so its logs already
hold rows past the checkpoint, which the restart must drop; every OpenFAST
restart-parity test runs this way.

``MovingBodies_Restart_ChangedBodyKey``, ``_ChangedAdmSpreading``, ``_ChangedStep``, ``_LaterStopTime``
and ``_AddedBody`` (``Tests/RunRestartAbort.cmake``) restart the same
checkpoint with one change each (a body's ``num_points_t``, its ``adm_spreading``, ``erf.fixed_dt``,
a stop time past the one OpenFAST was started with, a second body) and require
the restart to stop with a message naming it. ``MovingBodies_Restart_MalformedStatsOnRank1``
and ``_MalformedWakeOnRank1`` write the checkpoint on two ranks with the turbine
owned by rank 1 (the restart's log must say so), overwrite its statistics or wake-average file with a malformed
one, and require the restart to stop with that file's message: only the owner
reads the file, and every rank stops with its message (a rank that skipped the
reduction would hang until the 180 s limit). ``MovingBodies_CtDisk_Restart`` does the
same restart-parity check (with ``OVERRUN``) for the prescribed-Ct disk, asking
for a later stop time on restart, which a run without turbines may do, and
``MovingBodies_Restart_ChangedDiskDensity`` requires a changed ``air_density`` to
stop the restart. ``OpenFAST_ADM_Restart_WakeOwnerRank1`` repeats
``OpenFAST_ADM_Restart`` on two ranks with three 20-cell boxes in x, where the
turbine and its wake lines are owned by rank 1 (checked by
``MovingBodies_Owners_Wake``), so the wake files and the running sums in the
checkpoint come from rank 1. ``OpenFAST_ADM_TwoTurbines_Restart`` restarts the two-turbine
farm on two ranks with three 20-cell boxes in x (``amr.max_grid_size_x = 24``),
so the first turbine's logs and checkpoint
files are written, and on the restart trimmed, by rank 1, and requires every
turbine's logs to match. ``OpenFAST_ADM_TwoTurbines_RestartOnOneRank``
checkpoints the same farm on two ranks and restarts it on one, which then owns
both turbines and reads the files rank 1 wrote; plotfile and logs must agree
with the straight run to the roundoff of the FFT solution on another rank count
(the plotfile to the default tolerances, the logs to 8 digits).
``MovingBodies_DiagnosticsFormat_PerRank_RestartOnOneRank`` writes the farm's
logs one file per rank on two ranks, runs on past the checkpoint at step 5 to
step 10, and restarts on one rank with no step left: rank 1's files, which no
rank of the restarted run writes, must be cut back to a straight 5-step run's
bytes, and by the I/O rank (``Tests/RunTrimOnRestart.cmake``, which reads who
cut each file from the restart's log). ``MovingBodies_Restart_OwnersCutTheirLogs``
does the same on two ranks with one file per body: each turbine's files must be
cut once, by its owner (rank 1 for T1, rank 0 for T2), and the farm's totals by
the I/O rank. ``MovingBodies_Restart_WakeOwnerCutsItsLog`` checks the wake file
of a turbine owned by rank 1.

Test Location: `Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Restart`_

.. _`Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Restart`: https://github.com/erf-model/GALE/tree/development/Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Restart
