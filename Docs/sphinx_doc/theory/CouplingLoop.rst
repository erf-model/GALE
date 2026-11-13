The coupling step
=================

ERF talks to OpenFAST through its external-inflow C interface (``ExtInfw``, OpenFAST 5; the
interface is the same in 4.2). The OpenFAST model sets ``CompInflow = 2``, so the inflow comes
from ERF rather than from InflowWind.

Every step of the anchor level
------------------------------

#. **Sample.** ERF interpolates the flow velocity to OpenFAST's velocity nodes (hub, blade and
   tower structural nodes) and hands it to OpenFAST. For testing,
   ``erf.moving_bodies.prescribed_velocity`` replaces the flow.
#. **Step OpenFAST.** OpenFAST advances its own, smaller step ``n`` times. ``n`` is the bodies'
   step (``erf.fixed_dt`` divided by the time refinement down to the anchor level) over the
   OpenFAST ``DT``. ERF refuses to start when ``n`` is not a whole number.
#. **Read the loads.** OpenFAST returns the positions of its actuator force points and the
   aerodynamic force on each. Positions are in the turbine's frame with the tower base at the
   origin; ERF adds ``base_pos``. The first row of the hub's orientation matrix gives the shaft
   axis.
#. **Spread.** The forces, with the sign reversed to act on the fluid, are spread onto the
   momentum sources of the step ERF is about to take.

The models are initialised at start-up, so their inputs are checked then. OpenFAST's first solution
is taken at the first step, once there is a flow to sample.

Each turbine is owned by one MPI rank. Only that rank calls OpenFAST and holds the turbine's nodes
and loads. Each point goes from there only to the ranks whose boxes it touches; see
:doc:`Parallel`.

Velocity sampling
-----------------

Each velocity component is interpolated from its own staggered grid: ``u`` from the x faces, ``v``
from the y faces, ``w`` from the z faces. The interpolation is bilinear in the horizontal and
linear in the physical height within each column, using the face heights of ``z_phys_nd``.

- A field linear in x, y and the physical height is reproduced exactly, on every mesh type.
- A node is sampled by the rank whose box holds its cell, reading neighbours from ghost cells. The
  result does not depend on the domain decomposition.
- A node outside the domain aborts the run, naming its coordinates.

Force spreading
---------------

Each force point is spread onto ERF's face-centred momentum sources with a 3-D Gaussian kernel

.. math::

   \eta(\mathbf{x}) \propto \exp\!\left(-\frac{|\mathbf{x} - \mathbf{x}_p|^2}{\epsilon^2}\right),

cut off beyond :math:`3\epsilon`. Here :math:`\mathbf{x}_p` is the point and :math:`\epsilon` its
width, given in cells of the anchor level's ``dx``. Each kind of point has its own width; see
:doc:`TowerNacelle`.

**Discrete normalisation.** The kernel is normalised by its sum over the faces it reaches, on each
staggered grid, with the face volumes (``dx dy dz detJ`` on a terrain-fitted mesh). The source
therefore integrates back to the point force exactly, for every point and component, whatever the
resolution and however much of the kernel the ground or the domain top cuts off. The regression
tests check this identity in every row of the diagnostics.

- **Periodic boundaries.** Each point is also visited as its periodic images, so a kernel wraps.
- **Non-periodic boundaries.** Faces on the domain boundary get no source.
- **Cost.** It grows with the number of points and the cube of their widths, not with the mesh.
- **Timing within the step.** The sources are computed once per step: from the OpenFAST step just
  taken (turbines) or from the velocities at the start of the step (prescribed-Ct disks). They are
  added to the momentum right-hand side in every stage, before the anelastic projection removes
  their divergent part.

.. dropdown:: Why the normalisation is discrete

   Actuator codes in the AMR-Wind and SOWFA lineage (Kynema among them) divide each point's force
   by the analytic Gaussian volume :math:`\epsilon^3 \pi^{3/2}`. The sum over cells equals that
   volume only when the kernel lies wholly inside the domain, is resolved, and covers cells of one
   size. Otherwise the fluid does not receive the force the point carries, and nothing reports it:

   - The part below the ground or above the top is lost. A point at height :math:`h` loses
     :math:`\operatorname{erfc}(h/\epsilon)/2` of its force: about 14 % for the lowest IEA 15 MW
     blade tip with :math:`\epsilon = 40` m, and up to half for a tower point near the base.
   - Below about 0.75 cells the cell sum is no longer the integral. The 3-D sum over the analytic
     volume lies within 0.03 % of 1 at one cell, 0.98 to 1.02 at 0.75 cells and 0.6 to 1.6 at half a
     cell, depending on where the point sits.
   - On a stretched or terrain-fitted mesh the cell volumes vary across the kernel.

   The symptoms are a wake deficit slightly too weak, a thrust that depends on the grid and the
   rotor height, and momentum budgets that do not close. GALE pays a second pass per point to
   remove them.

.. dropdown:: Kernel ground cut: where the force goes

   A kernel cut by the ground is renormalised over what remains. The force is kept, but its centre
   moves up. For the lowest IEA 15 MW blade tip (30 m above the ground) the shift is 0.6 m with
   :math:`\epsilon = 20` m, 7.5 m with 40 m and 17 m with 60 m. The whole rotor's torque from the
   spread source then differs from the point loads' by 0.4 % at 40 m and 1.7 % at 60 m.

.. dropdown:: GPU kernels and determinism

   Each pass launches one GPU kernel per box and staggered grid, whatever the number of points.
   The periodic images are made once per point and binned to the boxes their kernels reach.

   - The normalisation pass gives each point one thread, which adds its terms in a fixed order
     (its images, then their faces).
   - The spreading pass gives each face one thread, which adds the terms of the images binned to
     its tile in point order.

   Neither uses atomic additions. The sources do not depend on how the device schedules its
   threads, and on a CPU they equal, to the last bit, those of spreading one point at a time. On a
   CPU the spreading pass runs no kernel: each image adds into the faces it reaches, in the same
   order. The device buffers are kept from step to step and grow to the largest exchange.

   The normalisation of a kernel is the sum of the parts the ranks it reaches compute on their own
   boxes. The owner adds them in rank order and sends the scaled force back.

Turbulent inflow
----------------

Nothing in the coupling depends on the lateral boundary conditions. A turbine can run in a
periodic box, with inflow and outflow fed from precursor planes (``erf.input_bndry_planes``), or
with a steady inflow profile and ERF's cell perturbation method (``erf.perturbation_type = CPM``).
The regression tests ``OpenFAST_ADM_LES`` and ``OpenFAST_ADM_CPM`` run the rotor both ways.
