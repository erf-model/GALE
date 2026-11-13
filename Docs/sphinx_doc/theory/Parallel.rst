Parallel runs
=============

Any number of bodies can be listed in ``bodies``. Each has its own input block and logs and, for an
OpenFAST turbine, its own OpenFAST instance.

Ownership
---------

Each OpenFAST turbine is owned by one MPI rank, chosen at start-up (and again on a restart, from
that run's boxes), in list order.

#. The **footprint** is the column of cells under the base, widened by the rotor radius from the
   model files (``TipRad`` of ElastoDyn, or the stub's ``rotor_radius``) and two cells.
#. The **candidates** are the least loaded ranks whose turbines step with the same OpenFAST ``DT``,
   or that own none.
#. A candidate with anchor-level boxes under the footprint takes it (the one holding most of it,
   then the lowest). Otherwise the candidate whose boxes come nearest takes it.

The turbines spread as evenly as dealing them out would, stand on their owner's boxes where that
costs no balance, and share a rank across time steps only when there are more time steps than
ranks. The run log names each owner.

Only the owner calls OpenFAST, holds the turbine's nodes and loads, applies the sampling corrections
and the FLLC, and writes the turbine's logs, statistics and checkpoint files.

- **Prescribed-Ct disks** get owners by the same rule among the disks alone. A disk runs no model,
  so it may share a rank with a turbine without holding up OpenFAST.
- **Wake lines** belong to their rotor's owner. Every rank keeps their geometry, so a restart on
  other ranks reads the running sums wherever the new owner is.

**One OpenFAST** ``DT`` **per rank.** OpenFAST keeps one step counter for all turbines of a process,
so a rank steps its turbines in turn, one OpenFAST step at a time. They must share ``DT``. The
owner choice ensures this whenever there are at least as many ranks as distinct ``DT`` values; the
run aborts otherwise. The stub enforces the same order.

Exchanges
---------

Each step the owner sends:

- each node to sample only to the ranks whose boxes may hold its cell, which send back the velocity;
- each point to spread only to the ranks whose boxes lie within its kernel's reach, which send back
  their part of the normalisation and receive the scaled force.

A rank that no point of a turbine reaches never receives its data. Disks join the same two
exchanges after the turbines; wake lines have one of their own at each step that writes them.

.. dropdown:: Envelopes: knowing whom to expect messages from

   Every rank keeps each body's envelope: a box holding its points and their kernels' reach,
   widened by the tip radius and two cells so a turning blade or yawing rotor stays inside (two
   cells for disks and wake lines, which stand still).

   Each exchange starts with one integer reduction saying whether any body's points have left its
   envelope. Only then are envelopes widened and shared, which a turbine that stays in place does
   in its first step only. ``envelope_check_interval`` makes this check collective only every N
   steps; between checks each owner checks its own points and aborts if they leave.

   The run log lists, for each turbine, disk and set of wake lines, the ranks it exchanges with.

Every turbine's numbers are gathered in four places only, a few numbers each: the farm totals in
``total_load.csv``, the checkpoint's ``state`` file, the start-up audit and the wake-line geometry.

Determinism
-----------

The result does not depend on which rank owns which body.

- On one or two ranks it equals, bit for bit, sampling and spreading every point on every rank
  (but for the sign of an exact zero).
- On more ranks the normalisations can differ in the last bits: the owner adds the ranks' parts in
  rank order, and an MPI reduction may not.

**Error messages.** A coverage failure is found by one integer reduction (turbines, then disks,
then wake lines), and its owner hands its message to every rank, so every rank stops with the same
message. The other checks on a body stop the run from the owner's rank; read that rank's message.

Farm totals
-----------

``<diagnostics_dir>/total_load.csv`` records the sum of every body's load on the structure (the
turbines' thrust, tower and nacelle forces, and the disks' thrust) and the turbines' total power.
Minus that load is what the integrated momentum source must equal. Wake lines are built behind
every rotor, so a downstream turbine's lines start behind it.
