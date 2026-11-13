Getting started
===============

This page builds GALE against the bundled OpenFAST stub and runs one turbine. No OpenFAST
installation is needed. For real turbines, see :doc:`Building`.

1. Clone
--------

.. code-block:: bash

   git clone --recursive https://github.com/erf-model/GALE.git
   cd GALE

2. Build
--------

.. code-block:: bash

   cmake -S . -B cmake-build -DERF_ENABLE_MPI=ON -DERF_ENABLE_FFT=ON \
         -DERF_ENABLE_OPENFAST=ON -DERF_OPENFAST_USE_STUB=ON
   cmake --build cmake-build -j

The executable is ``cmake-build/ERF/Exec/erf_exec``. ERF's
`Getting Started <https://erf.readthedocs.io/en/latest/GettingStarted.html>`__ page lists the
compilers and libraries it needs.

3. Run a case
-------------

Each folder in ``Exec/CanonicalTests/MovingBodies`` is a ready-to-run case. The actuator disk
in uniform inflow is a good first one:

.. code-block:: bash

   cp -r Exec/CanonicalTests/MovingBodies/OpenFAST_ADM_Uniform run-adm
   cd run-adm
   mpiexec -n 2 ../cmake-build/ERF/Exec/erf_exec OpenFAST_ADM_Uniform.i

It takes a few seconds: ten steps of a uniform 10 m/s flow through one rotor.

4. Look at the output
---------------------

==========================================  ===================================================
File                                        Contents
==========================================  ===================================================
``T1_erf.csv``                              rotor speed, thrust, torque, power, hub axis
``T1_flow.csv``                             velocity handed to the turbine at the hub and blade
                                            mean
``moving_bodies/momentum_source.csv``       force put into the flow; equals minus the thrust's
                                            shaft component
==========================================  ===================================================

The deck sets ``output_root = T1``, so the turbine's logs are in the run folder.
``momentum_source.csv`` rows carry the time at the start of a step and ``T1_erf.csv`` rows the time
at its end, so compare a ``momentum_source`` row with the ``T1_erf`` row one step earlier.

The full list is in :ref:`sec:Outputs`. ERF's plotfiles hold the flow with the wake.

Next steps
----------

- :doc:`CouplingToOpenFAST`: run your own turbine model.
- :doc:`Inputs`: every ``erf.moving_bodies`` key.
- :doc:`Limitations`: check these before planning a production run.
