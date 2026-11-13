GALE
====

**Generalized Actuator and Loads Engines** couples bodies that move in the wind to the
`ERF <https://github.com/erf-model/ERF>`__ atmospheric code. Its first bodies are wind turbines.

Each time step, ERF supplies the wind at the turbine's points. A body solver computes the loads:
`OpenFAST <https://openfast.readthedocs.io>`__, or a disk with a prescribed thrust coefficient.
GALE spreads the reaction force back onto the air, so the flow feels the turbine and forms its
wake. Every ERF capability (anelastic dynamics, terrain-fitted meshes, mesh refinement, LES and
RANS closures) is available to a GALE run.

.. grid:: 1 2 2 2
   :gutter: 3

   .. grid-item-card:: Getting started
      :link: GettingStarted
      :link-type: doc

      Build with the bundled OpenFAST stub and run a first turbine case in a few minutes.

   .. grid-item-card:: Setting up turbine cases
      :link: CouplingToOpenFAST
      :link-type: doc

      What the OpenFAST model needs, a minimal deck per rotor type, and recommended settings.

   .. grid-item-card:: How the coupling works
      :link: theory/MovingBodies
      :link-type: doc

      Sampling, force spreading, actuator disk and line, refinement levels, parallel layout.

   .. grid-item-card:: Limitations
      :link: Limitations
      :link-type: doc

      What a run requires, what is not supported, and where results need care.

.. rubric:: How GALE relates to ERF

GALE takes ERF as a git submodule (``Submodules/ERF``) and adds the structure model ``gale``
in ``Turbines/``. It builds on ERF's
`actuator core <https://erf.readthedocs.io/en/latest/theory/ActuatorCore.html>`__ and
`structure coupling <https://erf.readthedocs.io/en/latest/theory/StructureCoupling.html>`__,
and changes no ERF file. ERF's own inputs and build options are documented in the
`ERF documentation <https://erf.readthedocs.io/en/latest/>`__. These pages cover only what GALE
adds.

.. toctree::
   :caption: User guide
   :maxdepth: 1
   :hidden:

   GettingStarted
   Building
   CouplingToOpenFAST
   Inputs
   Limitations

.. toctree::
   :caption: Theory
   :maxdepth: 2
   :hidden:

   theory/MovingBodies

.. toctree::
   :caption: Verification
   :maxdepth: 1
   :hidden:

   RegressionTests
