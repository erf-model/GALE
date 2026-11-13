.. _sec:MovingBodiesInputs:

Inputs
======

All keys start with ``erf.moving_bodies.``. Per-body keys sit under
``erf.moving_bodies.<name>.``, one block per name in ``bodies``. The tables give the key without
the prefix.

General rules:

- ``erf.structures.model = gale`` turns the bodies on. Without it the keys are ignored, and
  ``amrex.parmparse.verbose = 1`` lists them as unused. With it, ``bodies`` must be set.
- Every value is range-checked at start-up. The run stops, naming the key, when one is out of
  range or not finite.
- A key the chosen options do not use gives a warning. One exception aborts: ``epsilon_tower``
  or ``epsilon_nacelle`` given while the tower or nacelle switch is not set at all.
- A restart must keep every key that places or forces a body. A change stops the run, naming
  the key. A key the body does not use may change: ``nacelle_area`` without ``nacelle_cd``, and
  ``correction_time`` with a fixed ``correction_relax``.
- Run requirements (solver, time step, levels, traps) are in :doc:`Limitations`.
- Every key is also in one annotated deck, :ref:`sec:MasterReference`.

Bodies
------

.. list-table::
   :header-rows: 1
   :widths: 26 46 14 14
   :class: inputs

   * - Key
     - Description
     - Values
     - Default
   * - ``bodies``
     - Names of the bodies.
     - strings
     - required
   * - ``<name>.type``
     - Kind of body.
     - ``openfast_turbine``, ``ct_disk``
     - required
   * - ``<name>.base_pos``
     - Tower base x, y, z (m). On a terrain-fitted mesh z is the height above the surface; 0 puts
       the base on the ground.
     - 3 reals
     - required
   * - ``<name>.output_root``
     - Prefix of the body's log files. Must be unique.
     - string
     - ``<diagnostics_dir>/<name>``
   * - ``<name>.air_density``
     - Density (kg/m³) used in the ``ct_disk`` thrust, nacelle drag, FLLC and corrected disk. Must
       equal the model's ``AirDens``.
     - > 0
     - 1.225

OpenFAST turbine
----------------

.. list-table::
   :header-rows: 1
   :widths: 26 46 14 14
   :class: inputs

   * - Key
     - Description
     - Values
     - Default
   * - ``<name>.fst_file``
     - OpenFAST primary file. See :ref:`the four settings <CouplingToOpenFAST>` it must hold.
     - string
     - required
   * - ``<name>.mode``
     - How loads reach the flow: as rings (disk), from the moving blade nodes (line), or not at
       all (one-way).
     - ``adm``, ``alm``, ``none``
     - ``adm``
   * - ``<name>.num_force_points_blade``
     - Force points per blade.
     - int > 0 (≥ 2 with FLLC)
     - 50
   * - ``<name>.num_force_points_tower``
     - Tower force points. 0 puts no tower force in the flow.
     - int ≥ 0
     - 0
   * - ``<name>.nacelle_cd``
     - Drag coefficient of a nacelle drag point at the hub. 0 is off.
     - ≥ 0
     - 0
   * - ``<name>.nacelle_area``
     - Nacelle frontal area (m²). Must be positive when ``nacelle_cd`` is.
     - ≥ 0
     - 0

Kernel widths
-------------

Widths are in cells of the anchor level's x spacing. See :doc:`theory/TowerNacelle` for how to
choose them.

.. list-table::
   :header-rows: 1
   :widths: 26 46 14 14
   :class: inputs

   * - Key
     - Description
     - Values
     - Default
   * - ``<name>.epsilon``
     - Width of the rotor's points (line nodes, disk rings, ``ct_disk`` points). Not with
       ``fllc = automatic``, which sets it.
     - > 0
     - 2.0
   * - ``<name>.epsilon_tower``
     - Width of the tower force points.
     - > 0
     - ``epsilon``
   * - ``<name>.epsilon_nacelle``
     - Width of the nacelle point. ``nacelle_cd × nacelle_area`` must not exceed
       :math:`2\pi\,\epsilon_{nacelle}^2` (in metres).
     - > 0
     - ``epsilon``

Actuator disk
-------------

For ``mode = adm``.

.. list-table::
   :header-rows: 1
   :widths: 26 46 14 14
   :class: inputs

   * - Key
     - Description
     - Values
     - Default
   * - ``<name>.num_points_t``
     - Points per ring.
     - int ≥ 2
     - 16
   * - ``<name>.adm_spreading``
     - One ring per blade node, or one shared ring per radial station.
     - ``rings``, ``merged_rings``
     - ``rings``
   * - ``<name>.sampling``
     - Where the velocity handed to OpenFAST comes from. See :doc:`theory/ActuatorDisk`.
     - ``disk``, ``upstream``, ``disk_corrected``
     - ``disk_corrected`` (adm), ``disk`` (alm, none)
   * - ``<name>.sample_diameters_upstream``
     - Distance ahead of the hub, in diameters, for ``upstream`` sampling (and ``ct_disk``).
     - > 0
     - 2.0 (turbine), 1.0 (``ct_disk``)
   * - ``<name>.correction_relax``
     - Under-relaxation of the recovered free stream. −1 chooses it from the loop gain; 1 is the
       unrelaxed update.
     - −1, or (0, 1]
     - −1
   * - ``<name>.correction_time``
     - Decay time (s) of a free-stream error with ``correction_relax = −1``. −1 is rotor radius
       over free stream; 0 is none.
     - −1, 0, or > 0
     - −1

Actuator line
-------------

For ``mode = alm``. FLLC is the filtered lifting-line correction.

.. list-table::
   :header-rows: 1
   :widths: 26 46 14 14
   :class: inputs

   * - Key
     - Description
     - Values
     - Default
   * - ``<name>.fllc``
     - Turns the FLLC on. ``automatic`` also sets ``epsilon`` (0.035 D), ``fllc_eps_chord`` (0.15),
       ``fllc_eps_dr`` (3), ``fllc_start_time`` (5 s) and 300 blade points. Giving any of them
       with ``automatic`` aborts.
     - ``true``, ``false``, ``automatic``
     - ``true`` (alm), ``false`` (adm, none)
   * - ``<name>.fllc_relax``
     - Relaxation factor of the correction.
     - (0, 1]
     - 0.1
   * - ``<name>.fllc_start_time``
     - Simulation time (s) from which the correction applies. This is ERF's time, not time since
       the bodies started.
     - ≥ 0
     - 0
   * - ``<name>.fllc_eps_chord``
     - Optimal kernel width, in chords.
     - > 0
     - 0.25
   * - ``<name>.fllc_eps_dr``
     - Span grid spacing is optimal width / ``fllc_eps_dr``.
     - > 0
     - 1.0
   * - ``alm_max_tip_cells``
     - Most cells a blade tip may sweep per step. Above it the run stops and names the largest
       ``erf.fixed_dt`` that passes.
     - > 0
     - 1.0

Prescribed-Ct disk
------------------

For ``type = ct_disk``. ``num_points_t``, ``sample_diameters_upstream`` and ``air_density`` also
apply.

.. list-table::
   :header-rows: 1
   :widths: 26 46 14 14
   :class: inputs

   * - Key
     - Description
     - Values
     - Default
   * - ``<name>.turbine``
     - Name of a turbine table, ``<turbine_data_dir>/<name>.txt`` (``NREL_5MW_126``, say; the
       list is in ``Turbines/Data/PowerCurves/README.md``). The radius is half the table's rotor
       diameter, and Ct is the table's Ct(U) at the upstream speed, zero outside the table. The
       table's Ct values must lie in [0, 2]. Not with ``ct`` or ``rotor_radius``.
     - table name
     - unset
   * - ``<name>.rotor_radius``
     - Disk radius (m). Not with ``turbine``.
     - > 0
     - required without ``turbine``
   * - ``<name>.hub_height``
     - Disk centre above the base (m). With ``turbine``, overrides the table's; required when the
       table gives no single hub height.
     - > ``rotor_radius``
     - required (table's with ``turbine``)
   * - ``<name>.ct``
     - Thrust coefficient on the upstream speed. Not with ``turbine``.
     - (0, 1)
     - required without ``turbine``
   * - ``<name>.yaw``
     - Disk normal, degrees from +x in the horizontal plane.
     - real
     - 0
   * - ``<name>.num_points_r``
     - Rings of the polar point grid.
     - int > 0
     - 8

Run-wide
--------

.. list-table::
   :header-rows: 1
   :widths: 26 46 14 14
   :class: inputs

   * - Key
     - Description
     - Values
     - Default
   * - ``anchor_level``
     - Level the bodies live on. −1 is ``amr.max_level``.
     - −1 to ``amr.max_level``
     - −1
   * - ``density_tolerance``
     - Allowed relative difference between ERF's density at a hub (or disk centre) and the model's.
     - ≥ 0
     - 0.05
   * - ``turbine_data_dir``
     - Folder of the turbine tables a ``ct_disk``'s ``turbine`` names. A relative path is relative
       to the run directory. An executable moved away from its source tree needs this key. Warned
       about when no ``ct_disk`` names a turbine.
     - path
     - ``Turbines/Data/PowerCurves`` of the GALE source tree
   * - ``prescribed_velocity``
     - Testing aid: a uniform velocity given to every node in place of the flow.
     - 3 reals
     - unset

Diagnostics
-----------

.. list-table::
   :header-rows: 1
   :widths: 26 46 14 14
   :class: inputs

   * - Key
     - Description
     - Values
     - Default
   * - ``diagnostics_int``
     - Steps between log rows.
     - int > 0
     - 1
   * - ``diagnostics_dir``
     - Folder of the logs.
     - string
     - ``moving_bodies``
   * - ``diagnostics_format``
     - One file per body, per rank, or per farm.
     - ``per_turbine``, ``per_rank``, ``farm``
     - ``per_turbine``
   * - ``avg_start``
     - Simulation time (s) from which statistics and wake averages accumulate.
     - ≥ 0
     - 0
   * - ``stats_int``
     - Steps between rewrites of the statistics and wake averages. 0 rewrites them at every write.
     - int ≥ 0
     - 0
   * - ``max_open_logs``
     - Most log files a rank keeps open. 0 takes a quarter of the open-file limit.
     - int ≥ 0
     - 0
   * - ``timing_int``
     - Steps between timing summaries per phase. 0 is off.
     - int ≥ 0
     - 0

Wake lines
----------

Lines behind every rotor: one horizontal and one vertical at each distance.

.. list-table::
   :header-rows: 1
   :widths: 26 46 14 14
   :class: inputs

   * - Key
     - Description
     - Values
     - Default
   * - ``wake.lines_xD``
     - Distances behind the rotor, in diameters.
     - reals > 0
     - unset (no lines)
   * - ``wake.half_width``
     - Half-length of each line, in diameters.
     - > 0
     - 1.5
   * - ``wake.num_points``
     - Points per line.
     - int ≥ 2
     - 61
   * - ``wake.int``
     - Steps between samples. 0 uses ``diagnostics_int``.
     - int ≥ 0
     - ``diagnostics_int``

Debugging and performance
-------------------------

.. list-table::
   :header-rows: 1
   :widths: 26 46 14 14
   :class: inputs

   * - Key
     - Description
     - Values
     - Default
   * - ``envelope_check_interval``
     - Steps between the collective check of the exchange envelopes. Between checks each owner
       checks its own points and aborts if they leave.
     - int ≥ 1
     - 1
   * - ``verify_tip_cells``
     - Checks the cached tip-travel cell heights against a fresh search every step.
     - true, false
     - false

.. _sec:MasterReference:

Master reference deck
---------------------

``Exec/CanonicalTests/MovingBodies/inputs_gale_master_reference`` lists every GALE key in one
file, with its default, range and units, grouped as above. Copy the lines a case needs. It is a
reference, not a runnable case: some keys in it exclude each other.

.. dropdown:: inputs_gale_master_reference

   .. literalinclude:: ../../Exec/CanonicalTests/MovingBodies/inputs_gale_master_reference
      :language: text
