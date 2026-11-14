Actuator line
=============

With ``mode = alm`` the blade force nodes themselves are the actuator points. After every OpenFAST
step, the positions it reports for the rotating, yawed and deflected blades
(``num_force_points_blade`` per blade, root to tip, plus the hub node) carry minus its node forces
into the spreading.

- The flow sees three moving lines of force and the tip and root vortices they shed.
- The integrated source equals minus the full thrust vector. No in-plane force is lost.
- Velocities are still sampled at OpenFAST's structural nodes. ``Wake_Mod`` must be 0, and the
  hub-axis check applies as for the disk.

Kernel width
------------

Hold the kernel at a fixed length as the mesh is refined: 0.035 rotor diameters (8.4 m for the
IEA 15 MW) with the FLLC. That is 0.84 cells on 10 m cells and 1.68 on 5 m cells.
``fllc = automatic`` sets it so. Held at a fixed number of cells instead, the kernel shrinks with
the mesh: 0.8 cells on 2.5 m cells (2 m) gave 15 % less power than OpenFAST.

Tip-travel limit
----------------

The line must not jump over cells between steps. Every step ERF computes the cells the blade tip
sweeps,

.. math::

   N_{tip} = \frac{\Omega\, R\, \Delta t}{\min(\Delta x, \Delta y, \Delta z)},

with :math:`\Omega` the rotor speed and :math:`R` the largest distance of a blade node from the hub
axis. It aborts when :math:`N_{tip}` exceeds ``alm_max_tip_cells`` (default 1), naming the largest
``erf.fixed_dt`` that passes. For the IEA 15 MW at rated speed (tip speed about 95 m/s) one cell
per step means :math:`\Delta t \le \min(\Delta x, \Delta y, \Delta z)/95` s, with :math:`\Delta t`
the anchor level's step, not ``erf.fixed_dt``. The check runs every
step because OpenFAST may change the rotor speed.

.. dropdown:: Effective :math:`\Delta z` on terrain and stretched meshes

   On a terrain-fitted or stretched mesh :math:`\Delta z` comes from the physical cells in the box
   the disk sweeps: the hub plus and minus :math:`R\sqrt{1 - n_d^2}` along each direction
   :math:`d` for the hub axis :math:`\mathbf{n}`, plus the blades' off-plane distance times
   :math:`|n_d|`.

   Each cell counts with its height divided by the largest share :math:`q_s` of the tip speed
   that can cross it.

   - The tip's vertical speed at a height of the disk is at most :math:`\Omega\sqrt{R^2 - r_z^2}`
     for any yaw, tilt or cone, with :math:`r_z` the vertical part of the tip's in-plane offset.
     So :math:`q = \sqrt{R^2 - d^2}/R`, with :math:`d` the distance from hub height to the cell's
     nearest point, less the off-plane distance times :math:`|n_z|`.
   - A tip moving sideways also crosses a sloping face. With :math:`G` the steepest slope of the
     cell's two faces, :math:`q_s = \min(\sqrt{1 + G^2},\, q + G)`.

   :math:`\Delta z` is the smallest height over :math:`q_s`. On a flat mesh a cell at hub height
   counts in full. On a stretched mesh, the short cells near the ground that the tip crosses
   mostly sideways do not stop a run. On the Askervein test the limit comes from a 43.9 m flank
   cell whose 22 degree faces make it count as 40.7 m; the guard's step is 0.96 of the exact one.

   The limiting height is searched for every rotor at the first step and after every regrid. It
   is searched again for a rotor only when its hub, tip radius, axis or off-plane distance has
   moved more than a tenth of the smallest cell size, as a floating platform's hub does. One
   integer reduction per step tells the ranks whether any has.
   ``erf.moving_bodies.verify_tip_cells = true`` checks the kept heights against a fresh search
   every step.

Filtered lifting-line correction (FLLC)
---------------------------------------

**Why.** A line spread with a kernel of several metres sees a weaker induced velocity at its own
points than a real blade, whose kernel is of the order of the chord. The blades then see too much
wind, and the line over-predicts power, more so for wider kernels.

**What it does.** The FLLC (Martinez-Tossas and Meneveau, 2019; generalized to variable chord by
Martinez-Tossas, Sakievich, Churchfield and Meneveau, *Wind Energy* 27:101, 2024) computes the
velocity that the line's own trailing vorticity induces at the line, for the kernel used and for
the optimal one. It adds the relaxed difference to the velocities OpenFAST receives at its blade
nodes. It is on by default with ``mode = alm``.

For each blade, with :math:`\mathbf{F}` the force on the fluid per unit density,
:math:`\mathbf{v}` the relative velocity (flow minus blade motion) and :math:`dr` the node width,
the lift per unit span is

.. math::

   \mathbf{G} = \frac{1}{dr}\left(\mathbf{F} - \mathbf{v}\,\frac{\mathbf{F}\cdot\mathbf{v}}{|\mathbf{v}|^2}\right),

and the induced velocity of the sources :math:`\mathbf{G}/|\mathbf{v}|` is

.. math::

   \mathbf{u}(r) = \frac{1}{2\pi} \sum_j \frac{\mathbf{G}_j}{|\mathbf{v}_j|} \, k(|r - r_j|, \epsilon_j) \, dr_j,
   \qquad k(r, \epsilon) = \frac{e^{-r^2/\epsilon^2}}{\epsilon^2} + \frac{e^{-r^2/\epsilon^2} - 1}{2 r^2}.

:math:`k` is the derivative form of the Gaussian-filtered vortex kernel; its far field is
:math:`-1/(2r^2)`. The correction is

.. math::

   \Delta\mathbf{u} \leftarrow (1 - f)\,\Delta\mathbf{u} + f\,(\mathbf{u}_{opt} - \mathbf{u}_{les}),

with :math:`f` = ``fllc_relax``, :math:`\mathbf{u}_{les}` computed with the line's ``epsilon`` and
:math:`\mathbf{u}_{opt}` with :math:`\epsilon_{opt}` = ``fllc_eps_chord`` × chord. It is a downwash
when the line's kernel is wider than the optimal one, and vanishes when they coincide.

- **Optimal width.** A quarter chord by default. ``fllc = automatic`` uses 0.15, the lower end of
  the optimal range 0.1 to 0.25, which matched OpenFAST better for the IEA 15 MW. The chord is
  OpenFAST's at each force node.
- **Span grid.** The sum runs over a fine grid of spacing :math:`\epsilon_{opt}` / ``fllc_eps_dr``,
  onto which :math:`\mathbf{G}/|\mathbf{v}|` and :math:`\epsilon_{opt}` are interpolated, since the
  optimal kernel is far narrower than the node spacing. The grid ends at the tip: a step that lands
  within :math:`10^{-6}` of a step short of it ends there, so the last spacing is never a rounding
  residue. The error in :math:`\mathbf{u}_{opt}` against a converged grid depends on how much load
  the tip carries. On the IEA 15 MW blade (50 to 300 points, :math:`\epsilon_{opt}/c` from 0.10 to
  0.25) with a load that stays finite at the tip, ``fllc_eps_dr`` = 1 gives 13 to 43 %, 2 up to 7 %,
  and 3 (the default) under 2 %. With a load that falls to zero at the tip, 1 gives 1 to 5 %.
- **Stability.** See :ref:`fllc-stability`.
- **Timing.** Computed from the loads of the step just taken, applied after sampling by linear
  interpolation along the span, starting at ``fllc_start_time``.
- **State.** Checkpointed. ``<output_root>_fllc.csv`` records its largest and RMS value.
- **Density.** Loads are divided by the body's ``air_density``, which must equal the model's
  ``AirDens``.

The implementation follows Kynema's variable-chord operator.

.. _fllc-stability:

Stability of the relaxation
~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Why.** The correction changes the velocity the blade sees, and so its lift, and the lift sets the
next correction. Too large a ``fllc_relax`` makes this loop overshoot and grow from one update to
the next.

**What sets the bound.** A correction :math:`\Delta u` along the lift direction changes the angle
of attack by :math:`\Delta u/|\mathbf{v}|`. The lift per unit span per unit density then changes by
:math:`\delta G = \tfrac{1}{2}\,c\,C_{L\alpha}\,|\mathbf{v}|\,\Delta u`, so the source
:math:`G/|\mathbf{v}|` changes by :math:`\tfrac{1}{2}\,c\,C_{L\alpha}\,\Delta u`. A span-wise
wave :math:`\Delta u \propto \cos(q r)` on a long blade of constant chord gives back the target

.. math::

   \delta(\mathbf{u}_{opt} - \mathbf{u}_{les}) = \lambda(q)\,\Delta u, \qquad
   \lambda(q) = -\frac{c\,C_{L\alpha}}{4\pi}\left[\hat{k}(q, \epsilon_{opt}) - \hat{k}(q, \epsilon)\right],
   \qquad \hat{k}(q, \epsilon) = \frac{\pi |q|}{2}\,\mathrm{erfc}\!\left(\frac{|q|\,\epsilon}{2}\right),

where :math:`\hat{k}` is the Fourier transform of :math:`k`, :math:`c` the chord,
:math:`C_{L\alpha}` the lift slope, :math:`\epsilon` the line's kernel and
:math:`\epsilon_{opt} = \epsilon_c\,c` with :math:`\epsilon_c` = ``fllc_eps_chord``. The minus sign
is the downwash: more lift, more correction against it. The update multiplies each wave by
:math:`1 - f + f\lambda`, which stays within :math:`(-1, 1)` while :math:`f < 2/(1 - \lambda)`.
:math:`\hat{k}(q, \epsilon)\,\epsilon` peaks at :math:`\pi x^* \mathrm{erfc}(x^*) = 0.7552`, where
:math:`x^* = |q|\epsilon/2 = 0.5316` solves :math:`\mathrm{erfc}(x) = 2x\,e^{-x^2}/\sqrt{\pi}`.
With a lift slope :math:`C_{L\alpha} = s \cdot 2\pi` and :math:`\epsilon \gg \epsilon_{opt}`, the
most negative :math:`\lambda` is :math:`-0.7552\,s/(2\epsilon_c)`, and the loop is stable for
:math:`f < 4\epsilon_c/(2\epsilon_c + 0.7552\,s)`. Tabulated airfoil slopes near zero lift exceed
the thin-airfoil :math:`2\pi`: the IEA 15 MW polars reach :math:`s` = 1.37. The check therefore
allows for :math:`s` = 1.4:

.. math::

   f < f_{max} = \frac{4\,\epsilon_c}{2\,\epsilon_c + 1.4 \times 0.7552}
               = \frac{4\,\epsilon_c}{2\,\epsilon_c + 1.057}.

The run stops at start-up when ``fllc_relax`` :math:`\ge f_{max}`.

.. list-table:: :math:`f_{max}` from the formula and from the eigenvalues of the discrete loop on the IEA 15 MW blade
   :header-rows: 1
   :widths: 16 14 35 35

   * - ``fllc_eps_chord``
     - Formula, :math:`s` = 1.4
     - Discrete, :math:`s` = 1.4
     - Discrete, :math:`s` = 1 (formula 0.797, 0.569, 0.419)
   * - 0.25
     - 0.642
     - 0.65 to 0.73
     - 0.80 to 0.89
   * - 0.15
     - 0.442
     - 0.45 to 0.51
     - 0.58 to 0.65
   * - 0.10
     - 0.318
     - 0.33 to 0.38
     - 0.43 to 0.50

The discrete values use 50 to 300 points per blade and :math:`\epsilon` from 5 to 10 m. For slopes
up to :math:`s \cdot 2\pi` the formula with that :math:`s` is a lower bound in every case tried
(320 cases, 20 to 1000 points, run kernels 2 to 20 m): a finite number of points cannot carry the
shortest waves, and a narrower run kernel only raises the bound. The margin goes to about zero as
the number of points grows. The bound assumes quasi-steady lift that answers the velocities of the
same update; loads that lag the velocities by one update lower it to about :math:`1/|\lambda|`.
The default 0.1 is stable for ``fllc_eps_chord`` above 0.028.
