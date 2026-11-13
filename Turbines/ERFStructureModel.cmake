# CMake: GALE's moving bodies (OpenFAST turbines and prescribed-Ct disks), compiled into ERF as
# structure model "gale". ERF includes this file for each directory listed in
# ERF_STRUCTURE_MODEL_DIRS and calls erf_structure_model_add with ERF's OBJECT library;
# ERF_STRUCTURE_MODEL_DIR holds this directory during the call. Tests/Unit includes the file a
# second time for erf_structure_model_add_unit_tests, so it holds definitions only.
#
# The OpenFAST options, the OpenFAST package search and the stub library (erf_openfast_stub) are
# set up in the top-level CMakeLists.txt, before ERF's library is made.
function(erf_structure_model_add target)
  set(_dir ${ERF_STRUCTURE_MODEL_DIR})
  target_sources(${target} PRIVATE
    ${_dir}/ERF_MovingBodies.cpp
    ${_dir}/ERF_GaleTurbineModel.cpp
    ${_dir}/ERF_MovingBodiesInputs.cpp
    ${_dir}/GaleCore/ERF_ActuatorRestriction.cpp
    ${_dir}/GaleCore/ERF_BodyExchange.cpp
    ${_dir}/GaleCore/ERF_CellHeights.cpp
    ${_dir}/GaleCore/ERF_OwnedWakeLines.cpp
    ${_dir}/GaleCore/ERF_UniformMeshNorm.cpp
    ${_dir}/ForceModels/ERF_PrescribedCtDisk.cpp
    ${_dir}/ForceModels/ERF_FLLC.cpp
  )
  # public: the unit tests include the model's headers
  foreach(_sub "" "/GaleCore" "/Motion" "/ForceModels")
    target_include_directories(${target} PUBLIC $<BUILD_INTERFACE:${_dir}${_sub}>)
  endforeach()
  if(ERF_ENABLE_OPENFAST)
    target_sources(${target} PRIVATE
      ${_dir}/OpenFAST/ERF_OpenFASTDriver.cpp
      ${_dir}/OpenFAST/ERF_OpenFASTAudit.cpp
      ${_dir}/ForceModels/ERF_OpenFASTRotor.cpp
    )
    target_include_directories(${target} PUBLIC $<BUILD_INTERFACE:${_dir}/OpenFAST>)
    target_compile_definitions(${target} PUBLIC ERF_USE_OPENFAST)
    if(ERF_OPENFAST_USE_STUB)
      target_link_libraries(${target} PUBLIC erf_openfast_stub)
    else()
      target_include_directories(${target} PUBLIC ${ERF_OPENFAST_INCLUDE_DIRS})
      target_link_libraries(${target} PUBLIC openfastlib ${ERF_OPENFAST_FORTRAN_LIBS})
      target_link_directories(${target} PUBLIC ${ERF_OPENFAST_FORTRAN_DIRS})
    endif()
  endif()
endfunction()

# The model's GoogleTest files, built into ERF's unit-test executable (erf_unit_tests).
# Tests/Unit/CMakeLists.txt, whose erf_parallel_tests has no model hook, also adds
# ERF_GTestBodyExchange, _GaleCellHeights and _GaleUniformMeshNorm to erf_parallel_tests, and
# ERF_GTestModelFacts there only.
function(erf_structure_model_add_unit_tests target)
  set(_dir ${ERF_STRUCTURE_MODEL_DIR}/Tests/Unit)
  # ERF's test helper ERF_GTestThrowOnAbort.H, which several of these tests include
  target_include_directories(${target} PRIVATE ${PROJECT_SOURCE_DIR}/Tests/Unit/MovingBodies)
  # Motivation: a turbine's owner must be a rank whose boxes overlap it, and its points, sampled and
  # spread through messages to the ranks whose boxes they touch only, must give what the global
  # sampler and spreader give over all the points; a rank no kernel reaches must receive nothing.
  # Motivation: the prescribed-Ct disk's point areas must sum to the disk area, its forces
  # to -T n with T from the upstream speed, and its inputs must be parsed with their ranges.
  # Motivation: GALE's copies of the wake lines and the running statistics (GaleCore), written and
  # restored by a body's owner, and its log helpers must pass the same checks as the originals, and the
  # log helpers must keep many files open within the open-file limit and trim a log at a checkpoint.
  # Motivation: the cell height that limits a blade tip must be the physical one, weighed by the tip
  # speed that crosses it, the same from the batched and the per-region search; a kernel's normalisation on
  # a uniform mesh, found on one rank, must be the sum of the ranks' partial norms.
  # Motivation: the timing summary (erf.moving_bodies.timing_int) must charge a phase's time to that
  # phase alone and only when it is on, and give each phase's minimum, mean and maximum over the ranks.
  # Motivation: an earlier version's checkpoint face forces must become the source F_f / dV_f, with
  # dV_f from the two cells beside the face on a terrain-following mesh, in every direction.
  target_sources(${target} PRIVATE
    ${_dir}/ERF_GTestActuatorRestriction.cpp
    ${_dir}/ERF_GTestBodyExchange.cpp
    ${_dir}/ERF_GTestPrescribedCtDisk.cpp
    ${_dir}/ERF_GTestOwnedWakeLines.cpp
    ${_dir}/ERF_GTestOwnedRunningStats.cpp
    ${_dir}/ERF_GTestGaleCellHeights.cpp
    ${_dir}/ERF_GTestGaleUniformMeshNorm.cpp
    ${_dir}/ERF_GTestPhaseTimers.cpp
  )
  if(ERF_ENABLE_OPENFAST AND ERF_OPENFAST_USE_STUB)
    # Motivation: the OpenFAST driver must keep the ERF step a whole multiple of the
    # OpenFAST step, accept only the anelastic solver with a fixed step, refuse a model
    # without external inflow, and report the stub's node layout on the owner rank; with tower
    # force points the tower nodes must carry the model's drag for the velocity supplied,
    # and the tower-shadow check must read TwrShadow; the turbines' owner ranks are given before
    # OpenFAST starts, and a farm runs its turbines as separate instances. The bundled stub library
    # stands in for OpenFAST.
    # Motivation: the actuator-disk rings built from a rotor's force nodes must lie in the
    # rotor plane at the nodes' radii and carry minus the rotor's force and torque exactly,
    # on a yawed and tilted axis as well as on x; a wrong hub axis must be detectable. The
    # actuator-line points must be the force nodes with the forces on the fluid, tower nodes
    # left out, and the tip travel per step must follow the rotor speed and the tip radius;
    # the tower points must be the tower nodes, and the nacelle drag must follow the drag law
    # with the kernel's self-induction correction; every point a turbine spreads must carry the
    # kernel width of its kind (rotor, tower, nacelle).
    # Motivation: the filtered lifting-line correction must reproduce the classical uniform
    # downwash of an elliptic lift distribution in the narrow-kernel limit, vanish when the run's
    # kernel is the optimal one, act against the lift for a wider kernel, relax as specified and
    # survive a checkpoint.
    # Motivation: the start-up audit must read the model's density, gravity and module files,
    # flag a density that differs from the body's or from ERF's at the hub, aerodynamics that
    # are off, a rotor outside the domain or overlapping another, a coarse mesh, a broken line
    # and a rotor facing away from the wind, as fatal or as warnings, and pass the stub by.
    # Motivation: the actuator-disk sampling mode must default to the corrected disk for
    # mode = adm and to plain disk sampling for an actuator line, keep an explicit choice, the
    # turbine's upstream sampling distance must default to two diameters, and the lifting-line
    # correction must be on by default for an actuator line only; the tower and nacelle widths must
    # default to epsilon, need their part forced, and enter the restart record.
    target_sources(${target} PRIVATE
      ${_dir}/ERF_GTestOpenFASTDriver.cpp
      ${_dir}/ERF_GTestOpenFASTRotor.cpp
      ${_dir}/ERF_GTestFLLC.cpp
      ${_dir}/ERF_GTestOpenFASTAudit.cpp
      ${_dir}/ERF_GTestMovingBodiesInputs.cpp
    )
    # the moving-bodies cases, whose model files (the IEA 15 MW models, the stub's decks) the readers are tested on
    target_compile_definitions(${target} PRIVATE
      ERF_GTEST_MOVING_BODIES_CASES="${PROJECT_SOURCE_DIR}/Exec/CanonicalTests/MovingBodies")
  endif()
endfunction()
