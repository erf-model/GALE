.. _sec:MovingBodies:

How the coupling works
======================

GALE puts wind turbines into an ERF flow. `OpenFAST <https://openfast.readthedocs.io>`__ computes
each turbine's aerodynamics and structural response; ERF supplies the wind and carries the wake.
The loads come from OpenFAST's blade-element solution on the turbine's own blade and tower nodes,
not from a thrust curve as in
`ERF's wind farm models <https://erf.readthedocs.io/en/latest/theory/WindFarmModels.html>`__.

.. grid:: 1 2 2 2
   :gutter: 3

   .. grid-item-card:: The coupling step
      :link: CouplingLoop
      :link-type: doc

      Sampling the flow, stepping OpenFAST, spreading the forces back.

   .. grid-item-card:: Actuator disk
      :link: ActuatorDisk
      :link-type: doc

      Rings, sampling modes and the corrected disk. Also the prescribed-Ct disk.

   .. grid-item-card:: Actuator line
      :link: ActuatorLine
      :link-type: doc

      Moving blade lines, the tip-travel limit and the filtered lifting-line correction.

   .. grid-item-card:: Tower, nacelle and kernel widths
      :link: TowerNacelle
      :link-type: doc

      How to choose each kind of point's width.

   .. grid-item-card:: Meshes and levels
      :link: MeshesAndLevels
      :link-type: doc

      Terrain, the anchor level and the force on coarser levels.

   .. grid-item-card:: Parallel runs
      :link: Parallel
      :link-type: doc

      Who owns a turbine, what is exchanged, and why results do not depend on the ranks.

   .. grid-item-card:: Run life cycle
      :link: RunLifecycle
      :link-type: doc

      Start-up audit, diagnostics, statistics, checkpoints and timing.

Code layout
-----------

- ``Turbines/ERF_GaleTurbineModel.cpp`` is the structure model ``gale``
  (`ERF's structure coupling <https://erf.readthedocs.io/en/latest/theory/StructureCoupling.html>`__).
  It is compiled in as any structure model is (``Turbines/ERFStructureModel.cmake``,
  ``Turbines/Make.package``) and selected with ``erf.structures.model = gale``.
- ``Source/MovingBodies/Core`` in ERF is the
  `actuator core <https://erf.readthedocs.io/en/latest/theory/ActuatorCore.html>`__: sampling,
  spreading, wake lines, running statistics. GALE uses it unchanged.
- ``Turbines/GaleCore`` holds what GALE adds to the core: the exchange of a body's points with the
  ranks it touches (``BodyExchange``), a kernel's normalisation summed on one rank, the tip-travel
  cell heights, the phase timers, logs for many bodies per rank (``LogStreams``), owner-written
  wake lines and statistics (``OwnedWakeLines``, ``OwnedRunningStats``), and the conversion of an
  old checkpoint's face forces (``ActuatorRestriction``).

ERF calls the model at the times it calls every structure model. It starts the bodies once the
mesh exists, steps them at each step of their level, and adds their momentum source on that level.
It then restricts that source onto the coarser levels, writes it to
``<chk>/StructureCoarseSource``, and stops the run when a finer level covers the bodies.

.. dropdown:: Uniform-dz meshes

   On a uniform-dz mesh ERF hands a structure model no heights or Jacobian. The model then gives
   the bodies the flat node heights ``prob_lo z + k dz`` and a Jacobian of 1, the values ERF holds
   on such a mesh. The bodies take the same code path on every mesh.

.. toctree::
   :hidden:

   CouplingLoop
   ActuatorDisk
   ActuatorLine
   TowerNacelle
   MeshesAndLevels
   Parallel
   RunLifecycle
