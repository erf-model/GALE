Tower, nacelle and kernel widths
================================

Tower and nacelle forces are off unless asked for, in either rotor mode. Each kind of point has
its own kernel width, in cells of the anchor level's ``dx``, and each body has its own set.

Tower
-----

With ``num_force_points_tower > 0`` OpenFAST is asked for that many tower force nodes, base to top.

- AeroDyn computes the drag from the velocities ERF samples at the tower nodes. ``TwrAero`` must be
  on. The stub applies a cylinder drag with its own ``tower_diameter`` and ``tower_cd``.
- ERF spreads each node's force with width ``epsilon_tower``, so the tower wake and its shadow on
  the rotor appear in the flow.
- AeroDyn's ``TwrShadow`` would count the shadow twice. ERF reads it and warns when it is not 0.

Nacelle
-------

With ``nacelle_cd > 0`` and ``nacelle_area``, ERF adds one drag point at the hub node:

.. math::

   \mathbf{f} = -\tfrac{1}{2}\,\rho\, c_d\, A\, |\mathbf{u}_c|\,\mathbf{u}_c,
   \qquad \mathbf{u}_c = \mathbf{u} \Big/ \left(1 - \frac{c_d A}{4\pi\epsilon_n^2}\right).

- :math:`\rho` is the body's ``air_density``, :math:`c_d A` = ``nacelle_cd`` × ``nacelle_area``
  and :math:`\epsilon_n` = ``epsilon_nacelle`` in metres.
- :math:`\mathbf{u}` is sampled at the hub node, also with ``sampling = upstream``.
- A Gaussian force of width :math:`\epsilon_n` lowers the velocity at its own centre by the factor
  :math:`1 - c_d A/(4\pi\epsilon_n^2)`, so the sampled velocity is divided by it. This is the
  correction Kynema applies with its own nacelle width.
- The run stops when the factor is under 0.5.

The tower force and the nacelle drag are logged with the thrust. The integrated momentum source
equals minus their sum.

Choosing the widths
-------------------

.. list-table::
   :header-rows: 1
   :widths: 20 30 50

   * - Key
     - Applies to
     - Guidance
   * - ``epsilon``
     - Line nodes, disk rings, ``ct_disk`` points
     - Line: fixed length, 0.035 D. Corrected disk: :math:`\epsilon \le 0.5 R`. The FLLC and the
       disk correction both use this width.
   * - ``epsilon_tower``
     - Tower force nodes
     - About :math:`2.8\, c_d d` keeps the drag about 10 % low (some 23 m for an 8 m tower).
   * - ``epsilon_nacelle``
     - Nacelle drag point
     - Factor :math:`1 - c_d A/(4\pi\epsilon_n^2) \ge 0.8` on two or more cells.

Unset, ``epsilon_tower`` and ``epsilon_nacelle`` take ``epsilon``. Bodies may use different widths,
for example a narrow actuator line beside a wide actuator disk; their sources add on the same
fields. The widths are part of the restart record.

Tower width
~~~~~~~~~~~

A tower node samples a velocity its own drag has already lowered. A line of drag
:math:`\tfrac{1}{2}\rho c_d d U^2` per unit length, spread with width :math:`\epsilon`, slows the
flow on its axis by the fraction

.. math::

   \frac{c_d\, d}{4\sqrt{\pi}\,\epsilon}

in linear theory. For an 8 m tower (:math:`c_d = 1`) that is about 11 % at 10 m and 6 % at 20 m;
with the drag taken from the lowered velocity, the drag comes out about 18 % and 10 % low. No
correction is applied. ``epsilon_tower`` lets the tower keep a wide kernel while the blades are
narrow. The start-up audit warns when the tower's force points lie farther apart than its kernel.

Nacelle width
~~~~~~~~~~~~~

For a 60 m² nacelle with :math:`c_d = 1` the factor is 0.24 at 2.5 m and 0.81 at 5 m.

.. dropdown:: Why the factor must stay above 0.5, and why 0.8 is recommended

   The correction is a linear estimate. Along the axis Bernoulli gives a sampled speed of
   :math:`U\sqrt{1 - 2 c_d A/(4\pi\epsilon_n^2)}`, which stagnates where the linear factor reaches
   0.5. Below that, the drag fed back through the corrected velocity is no longer a small change.
   The run therefore stops when :math:`c_d A > 2\pi\epsilon_n^2` (about 3.1 m is the least width
   for the nacelle above).

   That limit is where the correction stops making sense, not a target:

   - Near it the linear factor and Bernoulli part ways: their drag differs by 44 % at a factor of
     0.6 and 5 % at 0.81.
   - The velocity interpolated at the hub sees only part of the deficit, depending on where the
     hub sits in its cell: 60 to 100 % with the kernel one cell wide, 88 to 100 % at two. The
     corrected drag can then come out up to about twice the true one at the limit on one cell,
     and 25 % high on two.

   A factor of 0.8 or more on two or more cells keeps both effects to a few per cent. Kynema's
   choice :math:`\sqrt{2 c_d A/\pi}` gives a factor of 7/8 (6.2 m for that nacelle).

For the IEA 15 MW (:math:`c_d A` about 50 to 60 m²) a 2 m blade width gives a factor between about
0 and −0.19, which aborts; the nacelle then needs its own width (two 2.5 m cells give 0.81 to 0.84).
The recommended 8.4 m blade width gives 0.93 to 0.94, so one width serves both.

Width keys given without their force
------------------------------------

With ``mode`` adm or alm, a width given for a tower or nacelle aborts when its switch
(``num_force_points_tower``, ``nacelle_cd``) was never set, and warns when it was set to zero. With
``mode = none``, which forces nothing, it warns.
