Inputs
======

.. _sec:MovingBodiesInputs:

Moving Bodies (OpenFAST turbines)
---------------------------------

The moving-bodies framework couples ERF to OpenFAST turbines through OpenFAST's
external-inflow interface, and also drives prescribed-Ct disks that need no OpenFAST; see
:ref:`sec:MovingBodies` for the coupling. The framework and the ``ct_disk`` bodies are built
with ``-DERF_ENABLE_MOVING_BODIES=ON`` (cmake), which also compiles in the bodies' directory
``Turbines/``; ``openfast_turbine`` bodies need ``-DERF_ENABLE_OPENFAST=ON`` as well, which switches the
framework on by itself. GNU Make compiles the bodies when ``Turbines/`` is listed as a structure model
directory, as ``Exec/GNUmakefile`` does (:doc:`Building`): ``USE_MOVING_BODIES = TRUE`` with
``STRUCTURE_HOME`` naming GALE's ``Turbines``, and ``USE_OPENFAST = TRUE`` with ``OPENFAST_HOME``
set to the OpenFAST install prefix for ``openfast_turbine`` bodies.

The bodies run as the structure model ``gale`` (`ERF's structure coupling <https://erf.readthedocs.io/en/latest/theory/StructureCoupling.html>`__), which
``erf.structures.model = gale`` selects; their own inputs stay under ``erf.moving_bodies``.
Without that line the run has no bodies, and ``amrex.parmparse.verbose = 1`` lists the
``erf.moving_bodies`` keys as never read. ``erf.structures.model = gale`` without
``erf.moving_bodies.bodies`` aborts.

The run aborts at start-up, naming the input, unless it has:

- the anelastic solver and a fixed time step (``erf.fixed_dt``) whose step on the bodies' level
  (``erf.fixed_dt`` over the sub-cycling ratios down to it) is a whole multiple of every OpenFAST
  model's time step;
- a known stop time: ``stop_time``, or ``max_step`` times ``erf.fixed_dt``, or
  ``stop_datetime`` (ERF then ignores ``stop_time``, and the bodies use the seconds to the stop
  date); the span from the start to the stop time must be a whole number of ``erf.fixed_dt``
  steps, since ERF would cut the last one, unless ``max_step`` ends the run first;
- the bodies on one level, the anchor level (``erf.moving_bodies.anchor_level``), whose grids
  cover every body point with its kernel's reach; the coarser levels carry the anchor level's
  force summed onto their faces; no finer level may cover any of them (each turbine's hub with its
  tip radius, its tower and nacelle points and every disk, with the kernel's reach), since the
  average-down would overwrite the force there;
- with an ``openfast_turbine``, no floating-point traps (``amrex.fpe_trap_invalid``,
  ``amrex.fpe_trap_zero`` and ``amrex.fpe_trap_overflow`` all off), since OpenFAST raises
  exceptions of its own; runs with ``ct_disk`` bodies only may trap.

Every real input must be finite. Bodies are named in ``erf.moving_bodies.bodies``; each body
has its own ``erf.moving_bodies.<name>.*`` block. The common cases of a key that the chosen
options do not use (``fllc_relax`` with ``fllc = false``, say) are reported with a warning
(with ``mode`` adm or alm, ``epsilon_tower`` or ``epsilon_nacelle`` given while
``num_force_points_tower`` or ``nacelle_cd`` is not set at all aborts instead, as the width then
most likely meant the component to be on; a ``ct_disk`` warns about every key of an
``openfast_turbine``);
``amrex.parmparse.verbose = 1`` lists every input that was never read. The velocity at each
body's nodes is sampled from the flow every step unless ``erf.moving_bodies.prescribed_velocity``
is given.

A restart continues the same bodies with the same inputs: the bodies, the keys of their blocks
that place or force them under the chosen options (base_pos, epsilon, air_density, the model
file, mode, sampling and its keys, the force points, the nacelle, the widths of the tower and
nacelle points when they are forced, the FLLC keys; a ct_disk's
geometry, Ct and sampling distance), the anchor level and its step must match the checkpoint, and
with OpenFAST turbines the stop time must not lie past the one they were started with (OpenFAST
keeps it in its own checkpoint); the run aborts otherwise, naming the changed input. The diagnostics files keep
their rows up to the checkpoint and continue from there. A run started from a checkpoint
written without bodies (a precursor) starts the bodies afresh at the checkpoint's time.
A checkpoint of an earlier version, with the anchor level's source under ``moving_bodies/``,
is converted on the restart: the source is written into the checkpoint as
``StructureCoarseSource``. If the checkpoint cannot be written (read only), the levels
below the anchor take their first step after the restart without the bodies' force, and
the log says so. The bodies do not run with ``erf.terrain_type = EB``.

+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| Parameter                                              | Definition                                               | Acceptable Values        | Default                  |
+========================================================+==========================================================+==========================+==========================+
| **erf.moving_bodies.bodies**                           | names of the bodies, read with erf.structures.model =    | Strings                  | none (needed with        |
|                                                        | gale                                                     |                          | erf.structures.model =   |
|                                                        |                                                          |                          | gale)                    |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.type**                      | kind of body                                             | openfast_turbine,        | must be set              |
|                                                        |                                                          | ct_disk                  |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.base_pos**                  | tower base (m): x, y in ERF coordinates, z the height    | 3 Reals                  | must be set              |
|                                                        | above the terrain surface at (x, y), i.e. above the      |                          |                          |
|                                                        | k = 0 face there (on a flat mesh the absolute height);   |                          |                          |
|                                                        | 0 puts the base on the ground                            |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.epsilon**                   | Gaussian width of the force spreading, in units of the   | Real > 0                 | 2.0                      |
|                                                        | anchor level's x cell size: of the rotor's points (the   |                          |                          |
|                                                        | blade and hub nodes of an actuator line, the rings of a  |                          |                          |
|                                                        | disk, a ct_disk's points), and of the tower and nacelle  |                          |                          |
|                                                        | points unless their own widths are given; each body has  |                          |                          |
|                                                        | its own. For an actuator line hold it at a fixed length, |                          |                          |
|                                                        | about 0.035 rotor diameters, not a fixed number of       |                          |                          |
|                                                        | cells. Not with fllc = automatic, which sets it          |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.epsilon_tower**             | openfast_turbine, mode adm or alm, with                  | Real > 0                 | epsilon                  |
|                                                        | num_force_points_tower > 0: width of the tower force     |                          |                          |
|                                                        | points, in the same units                                |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.epsilon_nacelle**           | openfast_turbine, mode adm or alm, with nacelle_cd > 0:  | Real > 0                 | epsilon                  |
|                                                        | width of the nacelle drag point, in the same units;      |                          |                          |
|                                                        | also the width in its kernel correction, which needs     |                          |                          |
|                                                        | nacelle_cd * nacelle_area at most 2 pi                   |                          |                          |
|                                                        | epsilon_nacelle^2 (in metres), or the start-up audit     |                          |                          |
|                                                        | aborts                                                   |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.output_root**               | prefix of the body's diagnostics files, one per body     | String                   | <diagnostics_dir>/<name> |
|                                                        | (two bodies with one prefix abort); the files are        |                          |                          |
|                                                        | listed after this table                                  |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.fst_file**                  | openfast_turbine: OpenFAST primary input file; it must   | String                   | must be set              |
|                                                        | set ``CompInflow = 2`` (external inflow). Unless         |                          |                          |
|                                                        | ``mode = none``, its AeroDyn ``Wake_Mod`` must be 0 with |                          |                          |
|                                                        | ``sampling = disk`` (the actuator line, or a plain       |                          |                          |
|                                                        | disk) and not 0 with ``upstream`` or ``disk_corrected``  |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.mode**                      | openfast_turbine: how the OpenFAST loads reach the flow; | adm, alm, none           | adm                      |
|                                                        | ``adm`` spreads each blade node's force as a ring about  |                          |                          |
|                                                        | the hub axis, ``alm`` spreads it from the rotating blade |                          |                          |
|                                                        | node itself, ``none`` lets the turbine see the flow      |                          |                          |
|                                                        | without forcing it                                       |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.num_force_points_blade**    | openfast_turbine: actuator force points per blade        | Int > 0 (>= 2 with fllc) | 50                       |
|                                                        | requested from OpenFAST; fllc = automatic sets 300       |                          |                          |
|                                                        | (giving it with automatic aborts)                        |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.num_force_points_tower**    | openfast_turbine: actuator force points on the tower     | Int >= 0                 | 0                        |
|                                                        | requested from OpenFAST, whose tower loads are then      |                          |                          |
|                                                        | spread into the flow (0: the tower puts no force in it)  |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.nacelle_cd**                | openfast_turbine: drag coefficient of a nacelle drag     | Real >= 0                | 0                        |
|                                                        | point at the hub (0: no nacelle drag), on the velocity   |                          |                          |
|                                                        | at the hub and with air_density; nacelle_cd *            |                          |                          |
|                                                        | nacelle_area must not exceed 2 pi epsilon_nacelle^2      |                          |                          |
|                                                        | (epsilon_nacelle, or epsilon when it is not given, in    |                          |                          |
|                                                        | metres), or the start-up audit aborts                    |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.nacelle_area**              | openfast_turbine: frontal area of the nacelle (m^2);     | Real >= 0                | 0                        |
|                                                        | must be positive when nacelle_cd is                      |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.sampling**                  | openfast_turbine: where the node velocities handed to    | disk, upstream,          | disk_corrected (adm),    |
|                                                        | OpenFAST are sampled: disk (at the nodes); upstream      | disk_corrected           | disk (alm, none)         |
|                                                        | (sample_diameters_upstream diameters ahead of the hub    |                          |                          |
|                                                        | along the shaft, the free stream); or disk_corrected     |                          |                          |
|                                                        | (at the nodes, the free stream recovered from the disk   |                          |                          |
|                                                        | velocity with the filtered-disk factor of Shapiro et al. |                          |                          |
|                                                        | 2019 and momentum theory on the previous step's thrust,  |                          |                          |
|                                                        | under-relaxed by correction_relax). upstream and         |                          |                          |
|                                                        | disk_corrected need mode = adm; see fst_file for the     |                          |                          |
|                                                        | Wake_Mod each needs                                      |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.correction_relax**          | sampling = disk_corrected: under-relaxation factor f of  | -1, or 0 < Real <= 1     | -1                       |
|                                                        | the recovered free stream, new = (1 - f) old + f update; |                          |                          |
|                                                        | -1 takes f = 1 / (1 - G) from the update's loop gain G   |                          |                          |
|                                                        | (clamped to [0.2, 1]), which stops the step-to-step      |                          |                          |
|                                                        | overshoot above Ct of about 0.75, held at most           |                          |                          |
|                                                        | dt / (correction_time (1 - G)); a value in (0, 1] is     |                          |                          |
|                                                        | used as given, and 1 is the unrelaxed update             |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.correction_time**           | with correction_relax = -1: the time scale (s) on which  | -1, 0, or Real > 0       | -1                       |
|                                                        | an error of the free stream decays, so the update does   |                          |                          |
|                                                        | not ring at the delay with which the flow answers the    |                          |                          |
|                                                        | thrust; -1 is the rotor radius over the free stream, 0   |                          |                          |
|                                                        | none                                                     |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.fllc**                      | openfast_turbine, mode alm: filtered lifting-line        | true, false, automatic   | true (alm), false (adm)  |
|                                                        | correction of the velocities the blades are given.       |                          |                          |
|                                                        | automatic: on, with epsilon = 0.035 rotor diameters      |                          |                          |
|                                                        | (twice the model's TipRad; the anchor level's cells must |                          |                          |
|                                                        | then be at most 0.047 diameters), fllc_eps_chord = 0.15, |                          |                          |
|                                                        | fllc_eps_dr = 3, fllc_start_time = 5 and                 |                          |                          |
|                                                        | num_force_points_blade = 300; giving any of those keys   |                          |                          |
|                                                        | with it aborts                                           |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.fllc_relax**                | relaxation factor of the correction                      | 0 < Real <= 1            | 0.1                      |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.fllc_start_time**           | ERF's simulation time (s) from which the correction is   | Real >= 0                | 0                        |
|                                                        | applied: the time a restart or a precursor start carries |                          |                          |
|                                                        | on (7200 s, say), not the time since the bodies started; |                          |                          |
|                                                        | fllc = automatic sets 5 (giving it with automatic        |                          |                          |
|                                                        | aborts)                                                  |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.fllc_eps_chord**            | optimal kernel width in chords (OpenFAST's chord at each | Real > 0                 | 0.25                     |
|                                                        | force node); fllc = automatic sets 0.15 (giving it with  |                          |                          |
|                                                        | automatic aborts)                                        |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.fllc_eps_dr**               | fine span grid of the correction: spacing = optimal      | Real > 0                 | 1.0                      |
|                                                        | kernel width / fllc_eps_dr; fllc = automatic sets 3      |                          |                          |
|                                                        | (giving it with automatic aborts)                        |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.rotor_radius**              | ct_disk: disk radius (m)                                 | Real > 0                 | must be set              |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.hub_height**                | ct_disk: disk centre above the base (m); must exceed the | Real > rotor_radius      | must be set              |
|                                                        | radius                                                   |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.ct**                        | ct_disk: thrust coefficient on the speed sampled         | 0 < Real < 1             | must be set              |
|                                                        | upstream                                                 |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.yaw**                       | ct_disk: disk normal, degrees from +x in the horizontal  | Real                     | 0                        |
|                                                        | plane                                                    |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.num_points_r**              | ct_disk: rings of the polar point grid                   | Int > 0                  | 8                        |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.num_points_t**              | points per ring: of the ct_disk polar grid, or of the    | Int >= 2                 | 16                       |
|                                                        | rings an openfast_turbine's blade nodes are spread over  |                          |                          |
|                                                        | (mode = adm); the audit notes a ring spacing above       |                          |                          |
|                                                        | two kernel widths                                        |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.adm_spreading**             | openfast_turbine, mode = adm: rings (one ring per blade  | rings or merged_rings    | rings                    |
|                                                        | node) or merged_rings (one ring per radial station for   |                          |                          |
|                                                        | all the blades, at their mean radius with their summed   |                          |                          |
|                                                        | force: the same disk to rounding on a rigid rotor with a |                          |                          |
|                                                        | third of the points; the shaft force is kept, the torque |                          |                          |
|                                                        | is exact when the blades' radii agree); anything else    |                          |                          |
|                                                        | stops the run; may not change on restart                 |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.sample_diameters_upstream** | ct_disk, and openfast_turbine with sampling = upstream:  | Real > 0                 | 1.0 (ct_disk),           |
|                                                        | where the free stream is sampled, in diameters ahead     |                          | 2.0 (turbine)            |
|                                                        | along the normal / shaft axis                            |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.<name>.air_density**               | density (kg/m^3) in the ct_disk thrust, the nacelle      | Real > 0                 | 1.225                    |
|                                                        | drag, the lifting-line correction and the disk_corrected |                          |                          |
|                                                        | momentum theory; must equal the turbine model's AirDens. |                          |                          |
|                                                        | For a ct_disk the run aborts when it differs from ERF's  |                          |                          |
|                                                        | density at the disk centre by more than                  |                          |                          |
|                                                        | density_tolerance                                        |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.diagnostics_int**                  | write a diagnostics row every this many steps            | Int > 0                  | 1                        |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.diagnostics_dir**                  | directory of the default diagnostics files and of the    | String                   | moving_bodies            |
|                                                        | run's own files (listed after this table)                |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.diagnostics_format**               | where the bodies' time series and statistics go:         | per_turbine, per_rank,   | per_turbine              |
|                                                        | per_turbine (one file per body and log), per_rank (one   | farm                     |                          |
|                                                        | file per rank and log, written by the bodies' owners) or |                          |                          |
|                                                        | farm (one file per log, gathered to the I/O rank); the   |                          |                          |
|                                                        | last two carry the body's name in a body column          |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.stats_int**                        | rewrite the statistics (_stats) and the wake averages    | Int >= 0                 | 0                        |
|                                                        | (_wake_avg) every this many steps, at every checkpoint   |                          |                          |
|                                                        | and at the end of the run; 0 rewrites the statistics at  |                          |                          |
|                                                        | every diagnostics step and the wake averages at every    |                          |                          |
|                                                        | wake sample                                              |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.max_open_logs**                    | the most diagnostics files one rank keeps open at once;  | Int >= 0                 | 0                        |
|                                                        | opening one more closes the file written to most         |                          |                          |
|                                                        | recently, which is opened again to append; 0 takes a     |                          |                          |
|                                                        | quarter of the process's open-file limit (between 16     |                          |                          |
|                                                        | and 4096)                                                |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.prescribed_velocity**              | testing aid: the uniform velocity given to every body    | 3 Reals                  | none (velocities sampled |
|                                                        | node instead of the flow velocity; the sampling          |                          | from the flow)           |
|                                                        | correction and the FLLC still apply to it, so with       |                          |                          |
|                                                        | disk_corrected OpenFAST receives the recovered free      |                          |                          |
|                                                        | stream, not this velocity; no wake lines are sampled     |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.wake.lines_xD**                    | wake sampling lines behind every rotor at these          | Reals > 0                | none (no wake lines)     |
|                                                        | distances along its axis, in rotor diameters             |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.wake.half_width**                  | half-length of each line, in rotor diameters             | Real > 0                 | 1.5                      |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.wake.num_points**                  | points per line                                          | Int >= 2                 | 61                       |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.wake.int**                         | sample the lines every this many steps (0: every         | Int >= 0                 | diagnostics_int          |
|                                                        | diagnostics_int steps)                                   |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.avg_start**                        | ERF's simulation time (s) from which the wake running    | Real >= 0                | 0                        |
|                                                        | averages and the bodies' statistics accumulate (like     |                          |                          |
|                                                        | fllc_start_time, not the time since the bodies           |                          |                          |
|                                                        | started)                                                 |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.anchor_level**                     | the level the bodies are sampled and forced on; coarser  | 0 .. amr.max_level, or   | -1 (amr.max_level)       |
|                                                        | levels carry the anchor level's source restricted onto   | -1                       |                          |
|                                                        | their faces, which needs erf.coupling_type = TwoWay      |                          |                          |
|                                                        | above level 0 (none on a coarse step after a regrid of   |                          |                          |
|                                                        | the anchor level); no finer level may cover them         |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.density_tolerance**                | relative difference allowed between ERF's density at a   | Real >= 0                | 0.05                     |
|                                                        | hub and the OpenFAST model's AirDens, and at a ct_disk   |                          |                          |
|                                                        | centre and its air_density; the run aborts above it      |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.envelope_check_interval**          | check the bodies' exchange envelopes (the one reduction  | Int >= 1                 | 1                        |
|                                                        | of an exchange) on every this many steps only; between   |                          |                          |
|                                                        | checks each owner checks its points on its own and the   |                          |                          |
|                                                        | run aborts if they leave their envelope. For a turbine,  |                          |                          |
|                                                        | the margin is tip radius + 2 dx. Hub drift below the     |                          |                          |
|                                                        | margin minus the kernel reach (3 epsilon, using the      |                          |                          |
|                                                        | largest epsilon) between envelope builds guarantees      |                          |                          |
|                                                        | coverage. At a check, drift exceeding half the margin    |                          |                          |
|                                                        | since the last build triggers a rebuild.                 |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.alm_max_tip_cells**                | actuator line: the most cells a blade tip may sweep in   | Real > 0                 | 1.0                      |
|                                                        | one step (rotor speed times tip radius times the bodies' |                          |                          |
|                                                        | step over the smallest cell size; on a terrain-following |                          |                          |
|                                                        | or stretched mesh the physical cells the disk sweeps,    |                          |                          |
|                                                        | each height divided by the share of the tip speed that   |                          |                          |
|                                                        | can cross it, vertically or across a sloping face); the  |                          |                          |
|                                                        | run aborts above it, naming the largest ``erf.fixed_dt`` |                          |                          |
|                                                        | that passes                                              |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.verify_tip_cells**                 | actuator line, debugging: check every step the limiting  | true, false (or 1, 0)    | 0                        |
|                                                        | cell heights kept from step to step (searched again only |                          |                          |
|                                                        | after a regrid or when a rotor's box moves) against a    |                          |                          |
|                                                        | fresh search of each rotor's box; the run aborts if they |                          |                          |
|                                                        | differ                                                   |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+
| **erf.moving_bodies.timing_int**                       | print, every this many steps of the anchor level, the    | Int >= 0                 | 0 (off)                  |
|                                                        | wall-clock seconds each phase of the bodies took over    |                          |                          |
|                                                        | those steps (minimum, mean and maximum over the ranks)   |                          |                          |
|                                                        | and the OpenFAST step of the fastest and slowest         |                          |                          |
|                                                        | turbine; 0 prints nothing. Any build; with it on, each   |                          |                          |
|                                                        | timed phase waits for the GPU at its start and its end   |                          |                          |
+--------------------------------------------------------+----------------------------------------------------------+--------------------------+--------------------------+

The diagnostics files are listed below; they are written every ``diagnostics_int`` steps. The
rows of ``_erf.csv``, ``_flow.csv`` and ``total_load.csv`` carry the time at the end of their
step, and their first row holds the start-up state; the rows of the other files carry the time
at the start of the step whose forcing they describe.

- ``<output_root>_erf.csv`` (turbine): time, rotor speed (signed like the torque about the
  shaft), thrust vector, torque, power, hub axis, tower force, nacelle force and total load.
- ``<output_root>_flow.csv`` (turbine): the velocity handed to OpenFAST at the hub and its blade
  mean, after the sampling correction and the FLLC (not the raw sampled velocity).
- ``<output_root>_correction.csv`` (``disk_corrected``): disk velocity, inferred thrust
  coefficients, induction, filtered-disk factor, recovered free stream, the update's loop gain
  and the relaxation used.
- ``<output_root>_fllc.csv`` (FLLC): the correction's size.
- ``<output_root>_disk.csv`` (ct_disk): time, upstream speed, disk speed, thrust, power and the
  integrated source of all bodies projected on the disk's normal (the disk's own thrust when it is
  the only body).
- ``<output_root>_wake.csv`` and ``<output_root>_wake_avg.csv`` (wake lines): the instantaneous
  and running-averaged velocity along the lines.
- ``<output_root>_stats.csv``: running statistics from ``avg_start`` on, rewritten whole at each
  write (every ``stats_int`` steps, at checkpoints and at the end, when ``stats_int`` is set).
- ``<diagnostics_dir>/momentum_source.csv`` (the integrated momentum source, equal to minus the
  bodies' loads),
  ``total_load.csv`` (in a build with OpenFAST: the bodies' total load) and ``ground.csv`` (the terrain
  height under each body).

These are the files of ``diagnostics_format = per_turbine``. With ``per_rank``, the rows of the
``erf``, ``flow``, ``correction``, ``fllc`` and ``disk`` logs and the statistics of the bodies a rank
owns go to ``<diagnostics_dir>/rank<r>_<log>.csv`` (``r`` with five digits) instead; with ``farm``,
every body's go to ``<diagnostics_dir>/farm_<log>.csv``, written by the I/O rank from one reduction
per diagnostics step. Both add a ``body`` column (the body's name) after the time (first in the
statistics), and a body's rows, picked out by that column with the column removed, are its
``per_turbine`` rows. The wake-line files stay per body. The files are opened once and kept open:
their rows reach the disk at every checkpoint and at the end of the run (a run that aborts may lose
the rows written since its last checkpoint).
