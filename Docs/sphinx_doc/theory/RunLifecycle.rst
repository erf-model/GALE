Run life cycle
==============

Start-up checks
---------------

Before the flow exists, at start-up, GALE checks:

- the fixed step is a whole multiple of each OpenFAST ``DT``;
- ``CompInflow = 2``;
- ``Wake_Mod`` matches the sampling mode, and ``TwrShadow = 0`` with a forced tower.

Each distinct model is read on one rank (``erf_openfast::gather_model_facts``) and the results are
shared. The solver requirements (anelastic, fixed step, traps off with OpenFAST) are listed in
:doc:`../Limitations`.

Start-up audit
--------------

At the first step, once the node layout, the flow at the nodes and ERF's density at the hubs are
known, every OpenFAST turbine is audited. Findings are printed together under
``OpenFAST input audit for <name>``. A fatal finding aborts after the whole list is printed.

.. list-table::
   :header-rows: 1
   :widths: 50 50

   * - Fatal
     - Warning
   * - Model ``AirDens`` differs from ``air_density``
     - Model gravity differs from ERF's
   * - ERF's hub density differs from the model's by more than ``density_tolerance`` (an ABL base
       state thins with height, hence the tolerance)
     - Forced tower with ``TwrAero`` off
   * - ``CompAero = 0`` while loads go into the flow
     - Fewer than 8 cells across the rotor
   * - Rotor below the ground, above the top or across a non-periodic side
     - A kernel in use narrower than a cell, named by its key
   * - Base outside the domain
     - Line points farther apart than ``epsilon``; tower points farther apart than
       ``epsilon_tower``
   * - Two rotors whose swept discs intersect
     - ``num_force_points_tower > 0`` with a model that has no tower nodes
   * - ``nacelle_cd × nacelle_area`` above :math:`2\pi\epsilon_{nacelle}^2`
     - Rotor kernel cut by a non-periodic boundary; rotor facing away from the wind or yawed more
       than 30°

For a disk the audit also notes rings whose points lie more than two kernel widths apart, where the
ring's force breaks into separate blobs. With ``adm_spreading = line_to_disk`` it checks the spacing
of a sector's points instead (:doc:`ActuatorDisk`). The stub's deck is not an OpenFAST primary file, so its
model-file checks are skipped with a note. The tip-travel limit and the hub-axis check follow at
later steps.

Diagnostics
-----------

The files are listed in :ref:`sec:Outputs`. Some definitions:

- **Thrust** is the sum of the hub and blade node forces as OpenFAST reports them: the force of the
  fluid on the structure, so along the inflow. **Power** is torque times rotor speed.
- **Hub axis** is the shaft direction. It follows yaw, tilt and the tower's deflection.
- **Total load** is thrust plus tower plus nacelle, all on the structure.
- ``momentum_source.csv`` equals the sum of the forces on the fluid: minus the turbines' total
  loads (for an actuator disk, minus the thrust's shaft component), plus the prescribed-Ct disks'
  :math:`-T\mathbf{n}`.
- ``_erf`` and ``_flow`` rows carry the time at the end of their step; their first row is the
  start-up state. Files that describe a step's forcing carry the time at its start.

Wake lines
----------

``wake.lines_xD`` puts sampling lines behind every rotor (``OwnedWakeLines``, the owner-written copy
of the actuator core's ``WakeLines``).

- Each distance is along the horizontal projection of the rotor axis through the hub. A wake follows
  the wind at hub height, and a shaft tilt of a few degrees would otherwise carry far lines into the
  ground.
- At each distance: one horizontal line normal to that direction and one vertical line, each of
  ``num_points`` points spanning ``half_width`` diameters either side. The vertical line is clipped
  at the ground; each point's offset ``s`` is in the file.
- Lines are built at the first sample from the rotor's diameter. Every point must lie in the domain.
- Every ``wake.int`` steps the velocity is written to ``<output_root>_wake.csv``
  (``time, xD, line, s, x, y, z, u, v, w``) and, from ``avg_start``, accumulated into
  ``<output_root>_wake_avg.csv``.
- The running sums and the line layout are checkpointed. A restart with another layout stops.
- Nothing is sampled when ``prescribed_velocity`` replaces the flow.

Statistics
----------

From ``avg_start``, every step adds each body's state to its running statistics.
``<output_root>_stats.csv`` holds the sample count, first and last times and, per quantity, the
mean, RMS, minimum and maximum.

- **Turbine:** thrust along the shaft and along x, torque, power, rotor speed, hub velocity and
  blade-mean streamwise velocity.
- **Prescribed-Ct disk:** upstream and disk speeds, thrust and power.

The sums are checkpointed, so statistics continue across a restart. These are the numbers a
turbulent-inflow LES is compared on.

Checkpoint and restart
----------------------

An ERF checkpoint carries the bodies' state under ``<chk>/moving_bodies``:

.. list-table::
   :header-rows: 1
   :widths: 32 68

   * - File
     - Contents
   * - ``state``
     - Step count, start time, OpenFAST's stop time, anchor level and step, every body's placing
       and forcing inputs, each turbine's OpenFAST time index.
   * - ``<name>.chkp``
     - OpenFAST's own checkpoint (``FAST_CreateCheckpoint``), written by the owner.
   * - ``<name>_nodes.dat``, ``<name>_fllc.dat``
     - Node loads and the FLLC state.
   * - wake and statistics files
     - Running sums.

With an anchor level above 0, ERF writes the source the coarser levels need to
``<chk>/StructureCoarseSource``, as for every structure model.

**On restart:**

- Owners are chosen again from the new boxes; a restart may use another number of ranks.
- Turbines are restored with ``FAST_ExtInfw_Restart``. ERF checks that OpenFAST's time index is the
  one its own checkpoint expects.
- The anchor level's sources are rebuilt at the next step from the restored loads. Coarser levels
  take theirs from the stored source.
- With ``fllc = automatic`` the kernel width is set again from the restored rotor.
- Logs keep their rows up to the checkpoint and append from there. In a clean directory they start
  afresh.
- A checkpoint written without bodies (a precursor) can be restarted with bodies; they start afresh
  at its time.

The constraints on a restart are in :doc:`../Limitations`.

.. dropdown:: Checkpoints from earlier versions

   - One written before the bodies became structure model ``gale`` holds the source in
     ``moving_bodies/StructureCoarseSource``.
   - An older one holds the anchor level's face forces as ``moving_bodies/force_x``, ``force_y``
     and ``force_z``, which are turned into the source on the restart's grids.

   In either case, when ``<chk>/StructureCoarseSource`` is missing, the model writes it inside the
   checkpoint before ERF reads it. A checkpoint written before either was stored restarts with an
   unforced first coarse step, and the log says so.

Timing
------

Every phase is a ``BL_PROFILE`` region. A ``-DERF_ENABLE_TINY_PROFILE=ON`` build lists their times
at the end of the run (min, mean and max over ranks); in other builds they cost nothing.

``timing_int = K`` prints, in any build, every K anchor steps (counted across restarts), the
wall-clock seconds per phase since the last summary, as min, mean and max over ranks, and the
fastest, mean and slowest turbine's ``FAST_CFD_Step`` time.

.. dropdown:: Phases and their accounting

   The phases are ``startup`` (constructor, ``set_ground()``, ``read_checkpoint()``), ``advance``
   and its parts (``checks``, ``sample``, ``openfast``, ``diagnostics``, ``spread``,
   ``statistics``, ``wake``), then ``add_sources`` (every RK stage), ``check_levels`` and
   ``checkpoint``. A phase no rank spent time in is left out.

   - A region holding a collective includes the wait for the slowest rank.
   - OpenFAST's first solution is counted in ``openfast`` only.
   - The start-up is in a run's first summary, which after a restart may cover fewer than K steps.
   - The sources added in a summary's last step, and a checkpoint after it, count in the next one.
     What follows a run's last summary is not printed.
   - Each summary costs three reductions of 12 numbers and, with turbines, one number per turbine.
   - With the summary on, every phase waits for the GPU at its start and end, so it is charged for
     its own kernels only. Answers do not change either way.
