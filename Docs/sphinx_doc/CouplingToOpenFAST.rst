.. _CouplingToOpenFAST:

Setting up turbine cases
========================

This page lists what a case needs. How the coupling works is in :doc:`theory/MovingBodies`;
every input is in :doc:`Inputs`. The decks in ``Exec/CanonicalTests/MovingBodies`` are runnable
examples of every feature.

Turning the bodies on
---------------------

Two lines select GALE and name the bodies. Each body then has its own
``erf.moving_bodies.<name>.*`` block.

.. code-block:: text

   erf.structures.model     = gale
   erf.moving_bodies.bodies = T1 T2

The run must use the anelastic solver with a fixed time step, and floating-point traps must be off
with OpenFAST turbines. The full list of requirements is in :doc:`Limitations`. The run stops at
start-up, naming the input, when one is not met.

The OpenFAST model
------------------

Any standard OpenFAST model works. GALE reads four settings from it and checks them at start-up:

.. list-table::
   :header-rows: 1
   :widths: 22 34 44

   * - File and setting
     - Required value
     - Reason
   * - ``.fst`` ``CompInflow``
     - ``2``
     - ERF supplies the inflow.
   * - ``.fst`` ``AirDens``
     - ERF's density at the hub, within ``density_tolerance`` (5 %); equal to the body's
       ``air_density``
     - OpenFAST's loads go into ERF's air.
   * - AeroDyn ``Wake_Mod``
     - ``0`` with ``sampling = disk`` (and the actuator line); ``1`` with ``disk_corrected`` or
       ``upstream``
     - Induction is counted once: either by the resolved flow or by AeroDyn.
   * - AeroDyn ``TwrShadow``
     - ``0`` when tower force points are on
     - The tower's wake already reaches the blades through the flow.

Because of the ``Wake_Mod`` rule, one model file serves either the corrected disk or the line, not
both.

Time step
---------

The bodies' step must be a whole multiple of OpenFAST's ``DT``. The bodies' step is
``erf.fixed_dt`` divided by the time refinement down to the anchor level.

.. admonition:: Example

   With ``DT = 0.005`` s, ``erf.fixed_dt = 0.15`` works on two levels (0.075 s) but not on three
   (0.0375 s). ``0.16`` works on three (0.04 s).

An actuator line also has a tip-travel limit: the blade tip may sweep at most
``alm_max_tip_cells`` cells per step (default 1). The start-up message names the largest
``erf.fixed_dt`` that passes. The limit applies to the anchor level's step. For the IEA 15 MW the
power-curve runs used ``erf.fixed_dt`` of 0.15 s with a 10 m anchor level (two levels, 0.075 s
anchor step) and 0.16 s with a 5 m anchor level (three levels, 0.04 s).

Minimal decks
-------------

.. tab-set::

   .. tab-item:: Actuator disk

      The default and the configuration calibrated against standalone OpenFAST. The AeroDyn file
      must set ``Wake_Mod = 1``.

      .. code-block:: text

         erf.moving_bodies.T1.type      = openfast_turbine
         erf.moving_bodies.T1.mode      = adm
         erf.moving_bodies.T1.fst_file  = IEA15-land.fst
         erf.moving_bodies.T1.base_pos  = 750. 600. 0.   # z above the terrain surface
         erf.moving_bodies.T1.epsilon   = 2.0            # kernel width, in cells
         erf.moving_bodies.T1.num_points_t = 24

   .. tab-item:: Actuator line

      ``fllc = automatic`` sets the kernel width, the correction and 300 points per blade from the
      rotor size. The AeroDyn file must set ``Wake_Mod = 0``.

      .. code-block:: text

         erf.moving_bodies.T1.type      = openfast_turbine
         erf.moving_bodies.T1.mode      = alm
         erf.moving_bodies.T1.fst_file  = IEA15-land.fst
         erf.moving_bodies.T1.base_pos  = 750. 600. 0.
         erf.moving_bodies.T1.fllc      = automatic

   .. tab-item:: Prescribed-Ct disk

      No OpenFAST. A uniformly loaded disk with a closed-form thrust.

      .. code-block:: text

         erf.moving_bodies.D1.type         = ct_disk
         erf.moving_bodies.D1.base_pos     = 750. 600. 0.
         erf.moving_bodies.D1.rotor_radius = 120.
         erf.moving_bodies.D1.hub_height   = 150.
         erf.moving_bodies.D1.ct           = 0.75

Each deck also needs the solver lines:

.. code-block:: text

   erf.compressibility_type = Anelastic
   erf.timestepping_type    = MidPoint
   erf.vert_implicit        = true
   erf.use_fft              = true
   erf.fixed_dt             = 0.2
   amrex.fpe_trap_invalid   = 0

Recommended settings
--------------------

.. list-table::
   :header-rows: 1
   :widths: 20 80

   * - Topic
     - Recommendation
   * - Disk or line
     - Use the corrected disk for farms and RANS or ABL studies. Use the line with the FLLC for LES
       that resolves the blades.
   * - Disk kernel
     - Keep :math:`\epsilon \le 0.5 R`, so the filter width :math:`\sqrt{6}\,\epsilon` stays within
       1.25 rotor radii. Example: 1.5 cells of 40 m for a 120 m rotor.
   * - Line kernel
     - Hold it at a fixed length, 0.035 rotor diameters (8.4 m for the IEA 15 MW), not a fixed
       number of cells. ``fllc = automatic`` does this. Cells must then be at most 0.047 rotor
       diameters.
   * - Grid
     - At least 8 cells across the rotor. A fine patch around the rotor carries the bodies; no
       finer level may cover them.
   * - Boundaries
     - Inflow at ``xlo``, outflow at ``xhi``. No sponge around a single turbine. CFL at or below
       0.5.
   * - Terrain
     - Give ``base_pos`` z as the height above the surface. GALE places the body on the terrain.

Accuracy against standalone OpenFAST, IEA 15 MW, uniform inflow
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Fixed rotor speed, 10.59 m/s:

.. list-table::
   :header-rows: 1
   :widths: 56 22 22

   * - Disk set-up
     - Thrust / BEM
     - Power / BEM
   * - **disk_corrected (default), 20 m or 10 m cells**
     - **0.997 to 1.001**
     - **0.993 to 1.000**
   * - upstream sampling, two diameters ahead
     - 0.993
     - 0.999
   * - plain disk sampling, 20 m cells
     - 1.093
     - 1.328

With the ROSCO controller, error in power / thrust. ERF averaged over 300 to 360 s, OpenFAST
over 120 to 700 s, following the Kynema-SGF calibration by G. R. Yalla
(``gyalla/ALM_Calibrations``). Line: ``fllc = automatic``. Above rated (10.6 m/s) the controller
holds power, so thrust is the test.

.. list-table::
   :header-rows: 1
   :widths: 13 29 29 29

   * - U (m/s)
     - **Disk, 20 m (1 level)**
     - Line, 10 m (2 levels)
     - Line, 5 m (3 levels)
   * - 5.0
     - −0.2 % / −0.1 %
     - +1.4 % / +0.6 %
     - +3.7 % / +1.6 %
   * - 6.5
     - −0.2 % / −0.1 %
     - −1.1 % / −0.4 %
     - +1.3 % / +0.7 %
   * - 9.0
     - −0.2 % / −0.1 %
     - −3.8 % / −1.9 %
     - −1.1 % / −0.4 %
   * - 11.0
     - 0.0 % / +0.1 %
     - 0.0 % / +6.6 %
     - 0.0 % / +4.3 %
   * - 14.0
     - 0.0 % / 0.0 %
     - 0.0 % / +2.5 %
     - 0.0 % / +2.0 %

Decks, controller inputs and scripts are in ``Exec/CanonicalTests/MovingBodies/OpenFAST_IEA15_PowerCurve``.
The ROSCO library is not in the repository.

.. _sec:Outputs:

Outputs
-------

Logs are written every ``diagnostics_int`` steps. A body's files start with ``output_root``,
by default ``<diagnostics_dir>/<name>`` (``moving_bodies/T1``). A given ``output_root`` is used as
it is, relative to the run folder. The farm files are always in ``diagnostics_dir``.

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - File
     - Contents
   * - ``<root>_erf.csv``
     - Turbine: rotor speed, thrust vector, torque, power, hub axis, tower and nacelle forces,
       total load. Forces are on the structure.
   * - ``<root>_flow.csv``
     - Turbine: velocity handed to OpenFAST at the hub and blade mean, after corrections.
   * - ``<root>_correction.csv``
     - ``disk_corrected``: disk velocity, :math:`C_T`, induction, :math:`C_T'`, :math:`M`,
       recovered free stream, scale factor, loop gain, relaxation.
   * - ``<root>_fllc.csv``
     - Line with FLLC: largest and RMS correction.
   * - ``<root>_disk.csv``
     - ``ct_disk``: upstream and disk speed, thrust, power, integrated source along the normal.
   * - ``<root>_wake.csv``, ``_wake_avg.csv``
     - Velocity on wake lines, instantaneous and time-averaged.
   * - ``<root>_stats.csv``
     - Mean, RMS, min and max of each body quantity from ``avg_start``.
   * - ``momentum_source.csv``
     - Force put into the flow, integrated over the domain. Equals minus the bodies' load.
   * - ``total_load.csv``
     - Farm total load and power.
   * - ``ground.csv``
     - Terrain height under each body.

Rows of ``_erf``, ``_flow`` and ``total_load`` carry the time at the end of their step. The others
carry the time at the start of the step whose forcing they describe. OpenFAST writes its own
``.out`` files as configured in the ``.fst``.

``diagnostics_format = per_rank`` or ``farm`` gathers the per-body logs into one file per rank or
one per farm, with a ``body`` column.

Large farms
-----------

- Use at least as many ranks as turbines. A rank steps its turbines one after another.
- Write logs every 10 to 100 steps (``diagnostics_int``). OpenFAST's ``.out`` keeps the full rate.
- Sample wake lines rarely (``wake.int`` of 50 to 200 steps), only where needed.
- Use ``diagnostics_format = farm`` (or ``per_rank``) and ``stats_int`` of a few hundred steps.
- Measure with ``timing_int`` before tuning. A ``-DERF_ENABLE_TINY_PROFILE=ON`` build gives
  more detail.

Restarting
----------

Checkpoints hold the OpenFAST state and every running quantity, so a restart continues bit for
bit. It may use another number of ranks. It must keep the same bodies, inputs, anchor level and
``erf.fixed_dt``, and it may not run past the stop time the turbines started with (OpenFAST stores
it). The run stops, naming the input, otherwise.

To run past that stop time, copy the checkpoint, delete its ``moving_bodies`` folder and restart
from the copy. The turbines then start afresh at the checkpoint's time, as they do from a
precursor checkpoint written without bodies.
