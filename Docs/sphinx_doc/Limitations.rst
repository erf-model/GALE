Limitations
===========

This page collects what a GALE run requires, what it does not support, and where results need
care. Each item links to the theory behind it.

Run requirements
----------------

The run checks these at start-up and stops, naming the input, when one is not met.

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - Requirement
     - Detail
   * - Anelastic solver
     - ``erf.compressibility_type = Anelastic`` or ``PseudoIncompressible`` on every level. The
       compressible solver is not supported.
   * - Fixed time step
     - ``erf.fixed_dt``. The bodies' step must be a whole multiple of every OpenFAST ``DT``.
   * - Known stop time
     - ``stop_time``, ``max_step × erf.fixed_dt`` or ``stop_datetime``. The span must be a whole
       number of steps unless ``max_step`` ends the run first.
   * - Floating-point traps off
     - With OpenFAST turbines, ``amrex.fpe_trap_invalid``, ``_zero`` and ``_overflow`` must be 0.
       OpenFAST raises exceptions of its own. Runs with ``ct_disk`` bodies only may trap.
   * - Map factors of 1
     - Checked at every step of the anchor level.
   * - No EB terrain
     - The bodies do not run with ``erf.terrain_type = EB``. Terrain-fitted meshes are supported.
   * - Two-way coupling above level 0
     - With the anchor level above 0, ``erf.coupling_type`` must be ``TwoWay`` (the default).
   * - Same OpenFAST ``DT`` per rank
     - OpenFAST keeps one step counter per process. GALE keeps turbines of different ``DT`` on
       different ranks; this needs at least as many ranks as distinct ``DT`` values.

.. _sec:LimitsLevels:

Mesh and refinement
-------------------

- **One anchor level.** All bodies live on one level. Its grids must cover every body point with
  its kernel's reach, and every wake-line point. No finer level may cover the bodies, because
  the average-down would overwrite their force. See :doc:`theory/MeshesAndLevels`.
- **Coarse levels lag.** Each coarser level uses the anchor level's force from its previous step,
  about half a coarse step behind. The first coarse step of a run, and the first after a regrid
  of the anchor level, carry no body force.
- **FFT solver layout.** The refined region must be a rectangular union of boxes, as for any
  anelastic FFT run.
- **Refinement over terrain.** Refined levels on terrain-fitted meshes with turbines have been run
  for stability, not for accuracy. Two-level Askervein runs (build of 2026-11-09) converged with
  every terrain solver:

  ================================  =============  ==============  =============
  Refined level, after step 1       ``gmres_fft``  ``gmres_mlmg``  ``mlmg``
  ================================  =============  ==============  =============
  Largest divergence                7e-10          3e-10           1e-8
  Temperature range (K)             299.95–300.05  299.95–300.05   299.95–300.05
  Wall time, 4 ranks (s)            116            201             127
  ================================  =============  ==============  =============

  Earlier builds (2026-10-11) did not converge on the refined level. The changes since are
  erf-model/ERF#4279, #4280, #4337, #4879, #4902 and #4925, and the coarse-level body force.
  Three levels, and a refined level that stops inside the domain in z, were not rerun on
  Askervein. Check the divergence (``erf.mg_v = 1``) on every level of such a run.
- **Keep refinement away from the inflow.** A fine level whose boundary coincides with the inflow
  face gave an anomalous stable-ABL result.

Actuator disk
-------------

See :doc:`theory/ActuatorDisk`.

- **In-plane force is averaged away.** The disk keeps the shaft force and torque exactly. The net
  in-plane force, carried only by differences between blades, is lost in the flow.
- **Corrected disk: kernel range.** The correction factor was derived for filter widths up to
  1.25 rotor radii, so keep :math:`\epsilon \le 0.5 R`. Wider kernels give a warning.
- **Corrected disk: calibration.** The correction uses the twice-filtered form of Shapiro et al.
  (2019). Its 1 % agreement with BEM is a calibration, not a result of the theory alone.
- **Corrected disk: high thrust.** The thrust coefficient is clamped at 0.96. At the clamp, the
  induction stays at 0.4 and the recovered free stream reads a few per cent low; the first clamped
  step warns. A rotor spanning only 6 cells was seen to sit at the clamp.
- **Corrected disk: slow start.** The relaxed update takes about 3.4 time scales (some 40 s for
  the IEA 15 MW) to reach 1 % from a 30 % error.
- **Upstream sampling.** Sampling points keep their absolute height, so on a slope they can come
  close to or below the ground. A yawed rotor samples off to the side. The points must be on the
  anchor level.
- **Plain disk sampling** over-predicts loads on grids that do not resolve the disk: +33 % power
  on 20 m cells for the IEA 15 MW.

Actuator line
-------------

See :doc:`theory/ActuatorLine`.

- **Tip travel.** The tip may sweep at most ``alm_max_tip_cells`` cells per step. This limits the
  anchor level's step (``erf.fixed_dt`` over the time refinement down to it): about
  ``min(dx, dy, dz) / 95`` s for the IEA 15 MW at rated speed.
- **Minimum cell size for ``fllc = automatic``.** The kernel must be at least 0.75 cells, so cells
  must be at most 0.047 rotor diameters (11.2 m for the IEA 15 MW).
- **Settings tested on cubic cells.** The recommended settings were tested with
  ``dx = dy = dz``. Other aspect ratios print a note.
- **Mesh sensitivity.** At a fixed kernel length, 5 m cells give 2.4 to 2.7 points more power
  than 10 m cells below rated, and 0.5 to 2.3 points less thrust above rated.
- **Fewer blade points cost power.** 50 points per blade give about 2.5 points less power than
  300.

Kernels, tower and nacelle
--------------------------

See :doc:`theory/TowerNacelle`.

- **Kernels cut by the ground.** The force is kept, but its centre moves up. For the lowest IEA
  15 MW blade tip (30 m above ground) the shift is 7.5 m with :math:`\epsilon = 40` m, and the
  rotor torque changes by 0.4 %; at 60 m, 17 m and 1.7 %.
- **Narrow kernels.** Below about 0.75 cells the force is exact, but the kernel's shape depends on
  where the point sits in its cell.
- **Tower drag is not corrected.** A narrow tower kernel lowers the sampled velocity. An 8 m tower
  at ``epsilon_tower`` of 10 m gives about 18 % less drag; at 20 m, about 10 %.
- **Nacelle kernel.** The correction factor :math:`1 - c_d A / (4\pi\epsilon^2)` must be at least
  0.5, or the run stops. Near 0.5 the correction is inaccurate; keep it at 0.8 or more on two or
  more cells.

Parallel runs
-------------

See :doc:`theory/Parallel`.

- **One rank per turbine.** A rank steps its turbines one after another. Use at least as many
  ranks as turbines.
- **Last-bit differences on more than two ranks.** The owner adds the ranks' kernel parts in rank
  order; an MPI reduction may not. Results on one and two ranks match bit for bit.

Restart
-------

- **Same bodies and inputs.** A restart must keep the bodies, every key that places or forces
  them, the anchor level and its step.
- **Stop time.** With OpenFAST turbines, a restart may not run past the stop time the turbines
  started with. To go further, restart from a copy of the checkpoint without its
  ``moving_bodies`` folder; the turbines, statistics, wake averages and FLLC then start afresh.
- **Read-only old checkpoints.** A checkpoint from an earlier version is converted on restart. If
  it cannot be written, the coarse levels take their first step without the body force, and the
  log says so.

.. _sec:LimitsBuild:

Build and platforms
-------------------

- **GPU builds are compiled, not run, in CI.** The hosted runners have no GPU. CUDA, HIP and SYCL
  builds compile and link only.
- **No Windows CUDA build.** ``nvcc`` on Windows rejects extended device lambdas inside functions
  with internal linkage, which 26 ERF source files use. GALE's own kernels avoid this.
- **Windows CI runs serial tests only** (no MPI).
- **GNU Make is not tested** in CI.
- **Real-OpenFAST golds are per platform** (macOS and Linux). See :doc:`RegressionTests`.

ERF settings to watch
---------------------

- With a Dirichlet theta profile at the inflow, do not set ``<face>.density`` in an anelastic run:
  the inflow theta is scaled by the density ratio.
- On multi-level ABL runs, pin ``erf.max_geom_lscale``. The k-equation length-scale cap reads each
  level's own PBL height.
