Meshes and levels
=================

Bodies on terrain
-----------------

On a terrain-fitted mesh the z of ``base_pos`` is the base's height above the terrain surface at
its (x, y).

- The surface is the k = 0 node plane, interpolated bilinearly between the four nodes around the
  base. The height is added once at start-up, before OpenFAST is initialised or restored.
- On a uniform-dz mesh nothing is added, so z is the absolute height.
- The sampler and the spreader already work in the physical heights (``z_phys_nd``) and cell
  volumes (``detJ``), so nodes, rings and kernels follow the terrain without further change.
- The start-up audit measures ground clearance from the terrain under the hub. The vertical wake
  line stops at the terrain under its hub.
- The heights are written to ``<diagnostics_dir>/ground.csv`` (body, x, y, terrain height, base z).

The anchor level
----------------

On a run with refinement the bodies live on one level, the anchor: ``amr.max_level`` unless
``anchor_level`` names a coarser one.

- Nodes are sampled from that level's velocities.
- Sources are spread onto that level's faces, with the kernel width in that level's cells.
- OpenFAST steps with that level's fixed step (``erf.fixed_dt`` divided by the sub-cycling ratios).

A fine patch around a rotor thus gives an actuator line its few-metre cells without refining the
whole domain.

Force on coarser levels
-----------------------

Every coarser level carries the bodies' force too, with ``erf.coupling_type = TwoWay`` (the
default). At the start of each coarse step, the anchor level's latest source is restricted onto the
coarser faces by ERF's ``erf_structure::restrict_face_sources``
(`ERF's coarse-level source <https://erf.readthedocs.io/en/latest/theory/StructureCoupling.html#sec-structurecoarsesource>`__),
one level at a time. With :math:`F_f = s_f J_f \Delta x \Delta y \Delta z` the force on a fine face,

.. math::

   F_C = \sum_f w_f F_f, \qquad s_C = \frac{F_C}{J_C\, \Delta x_C\, \Delta y_C\, \Delta z_C}.

- :math:`s` is a momentum source (N/m³). :math:`J` is the face Jacobian: the mean of ``detJ`` in
  the two cells beside the face (the one cell inside at a non-periodic domain face; 1 on a
  uniform-dz mesh).
- In the face's own direction the sum runs over fine faces :math:`rI - (r-1)` to
  :math:`rI + (r-1)`, with :math:`r` the refinement ratio and linear weights
  :math:`w_f = 1 - |i_f - rI|/r`. Across it, over the fine faces that tile the coarse face.
- Each fine face's weights add to one, so every level carries the same total force, however narrow
  the kernel. The linear weights keep the centroid in the face's direction; across it the centroid
  may move by up to :math:`(r-1)/2` fine cells.
- On a non-periodic domain face a fine face inside the domain gives its whole force to the first
  coarse face inside.

**Why.** Without it a coarser level advanced and solved for its pressure as if the bodies were not
there. With sub-cycling, the anchor level then took boundary values from a flow that did not feel
them. A two-level disk with its fine box 0.8 R upstream saw 9.9 instead of 9.3 m/s a quarter
diameter ahead, and 12 % more thrust.

**Lag.** A coarse step uses the anchor level's source from its last step within the previous coarse
step: about half a coarse step behind. For the IEA 15 MW at 7.5 rpm with 0.2 s coarse steps, that is
under 6 degrees of rotation and 0.6 coarse cells of tip travel, in a region the average-down
overwrites anyway. The first coarse step of a run carries none, nor does a coarse step after a
regrid of the anchor level.

A checkpoint keeps the anchor level's source, so a restart gives the coarser levels the same
sources. Only the anchor level's source is written to ``momentum_source.csv``.

Coverage checks
---------------

**No finer level over the bodies.** The average-down would overwrite their force. After every
anchor step ERF aborts if the next finer level touches the bodies' support
(``MovingBodies::support_boxes()``):

- for each turbine, a cube about the hub of half-width the tip radius plus the kernel's reach
  (three widths and one cell), and the boxes of its tower and nacelle points with the same reach;
- for each disk, a cube about the hub of half-width its radius plus that reach.

**The anchor level must hold everything the bodies touch.** At the first step and whenever the
level's grids change, every node with its kernel's reach, every disk point and every wake point is
checked against the level's boxes (periodic directions wrap). A point outside aborts, naming it.
Enlarge the refinement region or choose a coarser anchor.

.. dropdown:: Coverage on terrain and stretched meshes

   On such meshes a point's cell is not its height over the nominal spacing. The cells a kernel may
   reach are found in the point's own columns, from the node heights of every column the kernel
   crosses, gathered in one collective so the answer does not depend on ranks or boxes.

   - The kernel needs the cells of those columns whose heights it spans. Where it crosses the
     bottom or top of the level's boxes, it needs the cell beyond too; a kernel the level cuts is
     refused.
   - The cells are one range per point, lowest to highest over its columns. A level with a height
     gap between two boxes may be asked for a few cells more than the kernel uses, never fewer.
   - A canyon floor elsewhere on the level does not raise the cells a plateau rotor needs.
   - A sampled point is checked over its whole column, since the sampler finds its cell itself.

The refinement region must also let the FFT solver run, as for any anelastic run: a rectangular
union of boxes.
