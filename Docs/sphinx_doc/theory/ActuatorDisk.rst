Actuator disk
=============

With ``mode = adm`` the loads OpenFAST computes on its blade nodes go into the flow as a disk, not
as rotating lines. OpenFAST still sees the true blade positions; only the flow does not.

Rings
-----

Each blade node, at radius :math:`r` from the hub in the plane normal to the shaft, becomes a ring
of ``num_points_t`` points at that radius, equally spaced in azimuth. Each point carries
:math:`1/N_t` of the node's force. The axial component is kept; the radial and tangential
components turn with the ring azimuth.

- **Kept exactly:** the force along the shaft and the torque about it.
- **Averaged away:** the net force in the rotor plane. A three-bladed rotor carries it only through
  differences between its blades at an instant.
- The integrated source equals minus the thrust's shaft component. The hub node keeps its own point.
- At the first step ERF checks that the blade nodes lie within about 20 degrees of the plane
  normal to the shaft axis, so a mismatched orientation convention aborts.

With ``mode = none`` the turbine is driven by the flow but puts no force into it, as for a loads
analysis in a precomputed flow.

Merged rings
~~~~~~~~~~~~

With ``adm_spreading = merged_rings`` the blades' nodes at the same radial station share one ring.
Blade :math:`b`'s node at station :math:`k` has distance :math:`a_{bk}` along the shaft, radius
:math:`r_{bk}`, and force components :math:`f^{c}_{bk}`, :math:`c \in \{x, r, \theta\}` (axial,
radial, tangential, on the fluid). The shared ring of the :math:`N_b` blades stands at the means and
carries the sums:

.. math::

   \bar a_k = \frac{1}{N_b} \sum_b a_{bk}, \qquad
   \bar r_k = \frac{1}{N_b} \sum_b r_{bk}, \qquad
   F^{c}_k = \sum_b f^{c}_{bk}.

- **Rigid rotor:** the same source as :math:`N_b` rings, to rounding, with :math:`1/N_b` of the
  points and of the spreading cost.
- **Shaft force:** kept for any rotor.
- **Torque:** differs at each station by
  :math:`\sum_b (r_{bk} - \bar r_k)(f^{\theta}_{bk} - F^{\theta}_k / N_b)`, which is :math:`N_b`
  times the covariance of the radii and the tangential loads. It is exact when the radii (or the
  tangential loads) agree.
- **Flexible rotor:** where the blades' deflections differ by :math:`\Delta a`, the source near the
  tip changes by about :math:`(\Delta a / \epsilon)^2` of itself. This is small when
  :math:`\epsilon` is several times the spread in deflection.

Sampling modes
--------------

The velocity at the rotor contains the rotor's own induction. The ``sampling`` mode decides who
accounts for it: the resolved flow or AeroDyn. ERF reads the AeroDyn file and checks
``Wake_Mod`` against the mode.

.. list-table::
   :header-rows: 1
   :widths: 18 40 16 26

   * - ``sampling``
     - Velocity handed to OpenFAST
     - ``Wake_Mod``
     - Behaviour
   * - ``disk``
     - At the blade nodes, inside the induction zone.
     - 0
     - Loads too high when the grid does not resolve the disk.
   * - ``upstream``
     - Shifted ``sample_diameters_upstream`` ahead of the hub, along the horizontal projection of
       the shaft.
     - 1 (BEMT)
     - BEM loads for that free stream, whatever the grid.
   * - ``disk_corrected`` (default)
     - At the blade nodes, scaled to the recovered free stream.
     - 1 (BEMT)
     - BEM loads from the disk velocity alone.

**Plain disk.** On a grid that does not resolve the smeared disk the sampled velocity is well above
the momentum-theory disk velocity. The IEA 15 MW disk on 20 m cells measured 33 % high in power
with a two-cell kernel, 29 % with 1.5 cells.

**Upstream.** In vortex-cylinder theory the rotor slows the flow one diameter ahead by 9 % of its
disk-averaged induction, two diameters ahead by 3 %. Each node keeps its own height, so a tilted
shaft does not move the points up or down. Limits are in :doc:`../Limitations`.

Corrected disk
--------------

The velocity a Gaussian-smeared disk samples is not the thin-disk velocity :math:`U_\infty(1-a)`
but that velocity divided by the factor of Shapiro, Gayme and Meneveau (2019, eq. 25):

.. math::

   M = \left( 1 + \frac{C_T'}{4} \frac{\Delta / R}{\sqrt{3 \pi}} \right)^{-1},
   \qquad C_T' = \frac{4 a}{1 - a} = \frac{C_T}{(1 - a)^2}.

- :math:`R` is the rotor radius and :math:`a` the axial induction.
- :math:`\Delta` is the width of their filter
  :math:`G = (6 / \pi \Delta^2)^{3/2} \exp(-6 r^2 / \Delta^2)`. ERF's kernel
  :math:`\exp(-r^2/\epsilon^2)` is that filter with :math:`\Delta = \sqrt{6}\,\epsilon`.
- The factor was derived for :math:`\Delta / R` up to about 1.25. Keep
  :math:`\epsilon \le 0.5 R`; wider kernels give a warning.

**Each step:**

#. Sample :math:`u_d`, the axial velocity over the blade nodes, each weighted by its radius times
   its share of the span.
#. Evaluate :math:`C_T` from the previous step's shaft thrust and free stream, clamped to 0.96.
#. Set :math:`a = (1 - \sqrt{1 - C_T})/2` and :math:`U_\infty = M u_d / (1 - a)`.
#. Scale the hub and blade node velocities by :math:`U_\infty / u_d`. Tower nodes keep the resolved
   flow. AeroDyn then applies its own induction.

The recovered free stream is checkpointed and logged in ``<output_root>_correction.csv``.

.. admonition:: Calibration, not theory alone

   The factor above is for the disk velocity filtered twice: by the force kernel and by a sampling
   kernel of the same width. GALE samples point values, filtered once; the same derivation then
   gives :math:`1/\sqrt{6\pi}` in place of :math:`1/\sqrt{3\pi}`. GALE keeps the twice-filtered
   form. With it the corrected disk matches the standalone BEM loads within 1 %; the once-filtered
   form recovers a free stream 3 to 4 % high on 20 m cells.

**The 0.96 clamp** is reached when the inferred thrust coefficient is that high: at high tip-speed
ratio, below rated at fixed speed, in a wake, or on a coarse grid (a rotor spanning only 6 cells sat
at the clamp). The induction then stays at 0.4, the recovered free stream reads a few per cent low,
and the first clamped step warns.

The actuator line keeps disk sampling. It resolves its own induction, and the filtered lifting-line
correction accounts for the kernel.

Under-relaxation
~~~~~~~~~~~~~~~~

**Why.** The free stream is recovered from the last one, through the thrust coefficient it implies.
Once the flow has answered the thrust, a small error in the previous free stream returns multiplied
by the loop gain

.. math::

   G = -\frac{2 a (1 - a)(1 - \delta)}{(1 - 2 a)(1 - a + \delta a)},
   \qquad \delta = \frac{\Delta / R}{\sqrt{3 \pi}}.

:math:`G` is negative (the update overshoots) and reaches :math:`|G| = 1` at
:math:`C_T \approx 0.75 + 0.11\,\Delta / R`. Above that the plain update alternates and grows until
the clamp stops it. A second mode comes from the flow: the disk velocity answers a thrust change
only after the induced flow builds up, and a faster update can ring at that delay. An 8 m LES of
the IEA 15 MW rang with a period of about 5 s.

The update is therefore relaxed:

.. math::

   U_\infty^{new} = (1 - \omega)\,U_\infty^{old} + \omega\,U_\infty^{update},

which turns the one-step gain into :math:`1 - \omega (1 - G)`.

**What the options do.**

- ``correction_relax = -1`` (default) takes :math:`\omega = 1/(1 - G)`, clamped to [0.2, 1], which
  cancels the step-to-step overshoot to first order. It also holds
  :math:`\omega \le \Delta t / (\tau (1 - G))`, so an error decays as :math:`e^{-t/\tau}` whatever
  the gain.
- :math:`\tau` is ``correction_time``: by default the rotor radius over the free stream, 11 s for
  the IEA 15 MW at 10.6 m/s. ``correction_time = 0`` keeps the gain factor alone.
- A fixed ``correction_relax`` in (0, 1] is used as given; 1 is the unrelaxed update.

The relaxation changes how the free stream is reached, not where it settles. The gain and
:math:`\omega` are logged in ``<output_root>_correction.csv``.

.. dropdown:: How the bound was chosen

   In a model of the loop where the flow answers the thrust after a delay and a lag:

   - the gain factor alone left the free stream ringing by 9 to 11 % for a 2 s delay
     (:math:`C_T` 0.85, :math:`\Delta / R` 0.16);
   - a bound of :math:`\Delta t / \tau` without the gain still rang by 3 to 7 % at the 0.96 clamp for
     delays of 6 to 10 s;
   - with :math:`\Delta t / (\tau(1 - G))` every case settled, within 1 % in 8 to 34 s.

   The cost is a slower start. From 30 % off, the free stream comes within 1 % in about 3.4 time
   scales (some 40 s for the IEA 15 MW) instead of a few steps.

Accuracy
--------

IEA 15 MW in a uniform 10.59 m/s inflow (open boundaries, no sponge, no turbulence closure), as a
ratio to the standalone OpenFAST BEM solution (thrust 2.482 MN, power 15.79 MW, momentum-theory
disk velocity 7.67 m/s):

================================================  =========  =========  =====================
Disk set-up                                       Thrust     Power      Sampled velocity (m/s)
================================================  =========  =========  =====================
disk sampling, 20 m cells, kernel 1.5 dx          1.084      1.288      8.40
disk sampling, 20 m cells, kernel 2 dx            1.093      1.328      8.47
disk sampling, 20 m cells, kernel 3 dx            1.112      1.403      8.63
disk sampling, 10 m cells, kernel 2 dx            1.072      1.243      8.36
upstream sampling 1 D, BEM on, 20 m and 10 m      0.977      0.954      10.43
upstream sampling 2 D, BEM on, 20 m               0.993      0.999      10.58
**disk_corrected, 20 m cells, kernel 2 dx**       **0.997**  **1.000**  8.74 → 10.77
**disk_corrected, 10 m cells, kernel 2 dx**       **1.001**  **0.993**  8.44 → 10.82
**disk_corrected, 20 m cells, kernel 3 dx**       **0.991**  **0.994**  8.99 → 10.67
================================================  =========  =========  =====================

- For the corrected disk the second velocity is the recovered free stream. It sits 1 to 2 % high,
  and the :math:`C_T` it implies (0.76 against BEM's 0.80) correspondingly low; the two biases
  cancel in the loads.
- The one-diameter upstream sample sits 1.5 % below the free stream because of the rotor's own
  induction. At two diameters, the turbine default, the bias is below 1 %.
- The ratios do not depend on the advection scheme (within 0.1 %). A periodic box changes them by 1
  to 2 %.
- These runs used the unrelaxed update. The correction settled within about 50 s with no
  oscillation.

Prescribed-Ct disk
------------------

``type = ct_disk`` is the classical test rotor: a uniformly loaded disk of radius :math:`R` and
normal :math:`\mathbf{n}`, covered by a polar grid of points. It runs no OpenFAST.

.. math::

   T = \tfrac{1}{2}\, \rho\, C_T\, U\,|U|\, \pi R^2 .

- :math:`U` is the area-weighted normal velocity sampled on the same grid
  ``sample_diameters_upstream`` diameters upstream; :math:`\rho` is the body's ``air_density``.
- Each disk point carries the share of :math:`-T\mathbf{n}` proportional to its area.
- :math:`U\,|U|` keeps the sign of the flow. A flow against the normal (:math:`U < 0`) gives
  :math:`T < 0`, so the disk slows it too. The sample plane then lies downstream of the disk, in
  its own wake, so this thrust is a drag that damps the reversed flow, not a momentum-theory
  thrust.
- The log records the upstream and disk-averaged speeds, the thrust, the power :math:`T U_d` and
  the integrated source along the normal. The ``power`` column is :math:`T U_d`, the rate of work
  the disk extracts from the flow, not the turbine's electrical power. It is negative only when
  the upstream and disk speeds have opposite signs (a turning flow), when the force speeds up the
  flow at the disk.
- The upstream sample still feels the disk. In vortex-cylinder theory at :math:`C_T = 0.75` it reads
  0.977 of the free stream one diameter ahead, so the thrust is 4.6 % below nominal; at two
  diameters it is 1.4 % below.
- ``air_density`` must match ERF's density at the disk centre within ``density_tolerance``.

With ``turbine = <name>`` the disk represents a published turbine. Its table
in GALE's turbine library (``Turbines/Data/PowerCurves/<name>.txt``, or
``erf.moving_bodies.turbine_data_dir``) gives the thrust coefficient
:math:`C_T(U)` and the electrical power :math:`P(U)` at a list of wind
speeds, and the rotor diameter. At every update

.. math::

   T = \tfrac{1}{2}\,\rho\,C_T(U)\,U\,|U|\,\pi R^2, \qquad R = D/2,

where :math:`U` is the sampled free-stream speed, :math:`\rho` is
``air_density`` and :math:`D` is the table's ``rotor_diameter``. Each table
:math:`C_T` must lie in [0, 2]; a constant ``ct`` lies in (0, 1). Between
rows :math:`C_T` and :math:`P` are interpolated linearly; below the first
and above the last speed (cut-in and cut-out) both are zero, so a parked
rotor puts no force in the flow. Table speeds are not negative, so a reversed
flow (:math:`U < 0`) gives a table disk no thrust. The tables were made at sea-level density,
1.225 kg/m\ :sup:`3`. The disk log then adds the columns ``ct`` and
``power_curve`` (the table's :math:`P(U)` in W; ``power`` stays :math:`T U_d`) for every disk of the run; a
constant-``ct`` disk in such a run logs its ``ct`` and ``T U_d``. Runs where
no disk names a turbine keep the five columns. The tables hold published
:math:`C_T` curves only. Turbines with only a power curve are left out:
:math:`C_T` from ideal momentum theory, :math:`C_p = 4a(1-a)^2`,
:math:`C_T = 4a(1-a)`, came out 29 to 34 % below the published
:math:`C_T` at peak :math:`C_p` for the eight NREL, IEA, DTU and LEANWIND
reference tables (25 to 37 % over all 44). The sources and licences of the
tables are in ``Turbines/Data/PowerCurves/README.md``.

The thrust jumps at the first and last table speeds: from zero to the
cut-in thrust, and from the cut-out thrust to zero. :math:`U` is the
instantaneous sampled speed, with no averaging and no hysteresis, so a disk
whose free-stream speed fluctuates about a cut-in or cut-out speed switches
its thrust on and off from one update to the next. Keep the inflow inside
the table's range when this matters.

The restart record of a disk holds its ``turbine`` name and its ``ct``
(zero with a table), so a restart that switches a disk between a table and
a constant ``ct``, or between tables, stops with a message. A table edited
in place under the same name is not detected. The default table folder is
the GALE source tree the code was built from; a relocated executable needs
``erf.moving_bodies.turbine_data_dir``.
