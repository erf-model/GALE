GALE: Generalized Actuator and Loads Engines
============================================

GALE couples bodies that move in the wind to the
`Energy Research and Forecasting (ERF) <https://github.com/erf-model/ERF>`__ atmospheric code.
Its first bodies are wind turbines. ERF supplies the wind at the turbine's blade and tower points;
a body solver (`OpenFAST <https://openfast.readthedocs.io>`__, or a prescribed thrust coefficient)
computes the loads; GALE spreads the reaction force back onto the air.

GALE takes ERF as a git submodule (``Submodules/ERF``) and adds to it the structure model
``gale`` in ``Turbines/``. The atmospheric code, its inputs and its build options are ERF's and
are documented in the `ERF documentation <https://erf.readthedocs.io/en/latest/>`__, in particular
the `actuator core <https://erf.readthedocs.io/en/latest/theory/ActuatorCore.html>`__ and the
`structure coupling <https://erf.readthedocs.io/en/latest/theory/StructureCoupling.html>`__ that
GALE builds on. These pages cover what GALE adds.

.. toctree::
   :caption: USER GUIDE
   :maxdepth: 1

   Building
   CouplingToOpenFAST
   Inputs
   RegressionTests

.. toctree::
   :caption: THEORY
   :maxdepth: 1

   theory/MovingBodies
