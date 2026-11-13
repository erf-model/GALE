# Moving-bodies cases

Regression cases for the moving-bodies framework (`erf.moving_bodies.*`:
OpenFAST turbines as actuator disks and lines, prescribed-Ct disks), laid out
like `../Canonical_RANS`: one directory per case with the input deck, the
bundled OpenFAST stub's turbine file where a turbine is involved, and the
gold logs the case is compared with. Each deck with bodies selects them with
`erf.structures.model = gale`, the bodies' structure model. They are registered in
`Turbines/Tests/ERFTurbinesTests.cmake` (`TEST_SOURCE_ROOT` points the registration here) and
their gold plotfiles stay in `Tests/ERFGoldFiles/<case>`. The theory and the
inputs are in `Docs/sphinx_doc/theory/MovingBodies.rst` and
`Docs/sphinx_doc/Inputs.rst`; what each test checks is in
`Docs/sphinx_doc/RegressionTests.rst`.

Every case builds with `ERF_ENABLE_OPENFAST=ON`, `ERF_OPENFAST_USE_STUB=ON`,
`ERF_ENABLE_FFT=ON` and MPI (`Actuator_UniformCtDisk` needs only
`ERF_ENABLE_MOVING_BODIES=ON`, and `Actuator_CtDisk_TwoLevel` needs
`ERF_ENABLE_MOVING_BODIES=ON`, FFT, MPI and Python 3), runs the anelastic solver on a small uniform
box for ten steps or so, and is checked by the runner named below. The two
Askervein cases are the exception: a 6 km x 3 km terrain-fitted domain, and the real OpenFAST library
(`ERF_OPENFAST_USE_STUB=OFF`, label `openfast-real`) on the IEA 15 MW model in
`IEA15_land_model` (see its README for the source, licence and changes) and the
terrain file of `Submodules/ERF/Exec/CanonicalTests/Real_Terrain/Askervein`, both copied next to the deck by the test.
Their golds are per platform, `*.macOS.gold` and `*.Linux.gold` here and `_macOS` and `_Linux` in
`Tests/ERFGoldFiles`: the two platforms agree exactly for four steps, then the line's and the disk's
corrections amplify a last-bit difference in a filter to 4e-3 relative in the power by step ten
(`Turbines/Tests/ERFTurbinesTests.cmake` and `Docs/sphinx_doc/RegressionTests.rst` give the numbers).
Refresh a gold set on the platform it belongs to.

| case | body | runner | what it checks |
| --- | --- | --- | --- |
| `OpenFAST_DriverOnly` | stub turbine, `mode = none` | `RunOpenFASTADM.cmake` | the flow is unchanged (the gold is the deck run without bodies); the turbine log matches its gold; no momentum source is written |
| `Actuator_Sampling` | stub turbine, `mode = none` | `RunActuatorSampling.cmake` | sampled velocities at the nodes against the analytic shear |
| `Actuator_UniformCtDisk` | prescribed-Ct disk | `RunCtDisk.cmake`, `RunRestartParity.cmake` | plotfile and disk log against their golds; the disk's force integrates back exactly; restart parity with a later stop time; a changed `air_density` stops a restart; with wake lines, ownership parity (one box against the disk owned by rank 1) and restart parity with the disk on rank 1, on two ranks and from two ranks to one |
| `OpenFAST_ADM_Uniform` | stub turbine, disk | `RunOpenFASTADM.cmake` | plotfile, sampled flow log, `fx == -thrust_x` |
| `OpenFAST_ADM_Upstream` | stub turbine, disk, velocities sampled 1 D upstream | `RunOpenFASTADM.cmake` | plotfile, sampled flow log, `fx == -thrust_x` |
| `OpenFAST_ADM_Terrain` | stub turbine, disk, on a Witch-of-Agnesi ridge (fitted mesh) | `RunOpenFASTADM.cmake` | ground heights log, plotfile, `fx == -thrust_x` |
| `OpenFAST_ADM_UpstreamNacelle` | stub turbine, disk, sampled one diameter upstream, nacelle drag | `RunOpenFASTADM.cmake` | plotfile and the nacelle column of the turbine log against golds made before the turbines' points were exchanged point to point; `fx == -load_x` |
| `OpenFAST_ADM_DiskCorrected` | stub turbine, disk, free stream recovered with the filtered-disk factor | `RunOpenFASTADM.cmake`, `RunRestartParity.cmake` | plotfile, flow log, `fx == -thrust_x`; restart parity of every log; with `correction_relax = 1` (`OpenFAST_ADM_DiskCorrected_OldUpdate`) the gold of the unrelaxed update |
| `OpenFAST_ADM_Wake` | stub turbine, disk, wake lines | `RunOpenFASTADM.cmake` | wake running average |
| `OpenFAST_ADM_Restart` | stub turbine, disk | `RunRestartParity.cmake` | restart parity of the plotfile and every log, with rows written past the checkpoint dropped; the restart aborts (changed body key, step, later stop time, added body) |
| `OpenFAST_ADM_LES` | stub turbine, disk, precursor planes | `RunPrecursorInflow.cmake` | turbulent inflow from a precursor; body statistics |
| `OpenFAST_ADM_CPM` | stub turbine, disk, cell perturbations | `RunOpenFASTADM.cmake` | turbulent inflow from the perturbation method; statistics |
| `OpenFAST_ADM_TwoTurbines` | two stub turbines, disks | `RunOpenFASTADM.cmake`, `RunRestartParity.cmake` | a farm: `fx == -load_x` of `total_load.csv`; ownership parity (one rank against two, with T2 owned by rank 1); restart parity on two ranks, with T1's logs and checkpoint files written by rank 1; restart on one rank from a two-rank checkpoint |
| `OpenFAST_ADM_TwoWidths` | two stub turbines, disks, a kernel width each | `RunOpenFASTADM.cmake` | plotfile, T2's flow log, `fx == -load_x` |
| `OpenFAST_ADM_DiskAndTurbine` | stub turbine (disk, 2 cells) and a prescribed-Ct disk (1 cell) | `RunOpenFASTADM.cmake` | the disk's log, `fx == -load_x` of both bodies; with the two swapped, ownership parity with the disk on rank 1 (`total_load.csv` gathered from it) |
| `OpenFAST_ADM_TwoLevel` | stub turbine, disk, on level 1 of two | `RunOpenFASTADM.cmake` | the anchor level: sampled and forced on the fine patch, stepped with its step; level 0 carries the source restricted onto its faces |
| `OpenFAST_ADM_TwoLevel_Restart` | as above | `RunRestartParity.cmake`, `make_legacy_checkpoint.py` | restart parity with the fine level, every log; `OpenFAST_ADM_TwoLevel_RestartLegacy`: a restart from the step-5 checkpoint rewritten by `make_legacy_checkpoint.py` into an earlier version's layout (face forces in `moving_bodies/force_x`, `_y`, `_z`) matches the straight run to 1e-10; `OpenFAST_ADM_TwoLevel_RestartBodiesDir`: the same with the source in `moving_bodies/StructureCoarseSource`, matched exactly |
| `Actuator_CtDisk_TwoLevel` | prescribed-Ct disk on one level and on level 1 of two, the fine box tight around it | `RunDiskLevels.cmake` | the coarse level carries the disk's force: the two runs' induction (disk-averaged and upstream velocity deficits) agree within 10 % |
| `OpenFAST_ALM_Uniform` | stub turbine, line | `RunOpenFASTADM.cmake` | the rotating line; tip-travel limit |
| `OpenFAST_ALM_Tower` | stub turbine, line, tower, nacelle | `RunOpenFASTADM.cmake` | `fx == -load_x` with the tower and nacelle |
| `OpenFAST_ALM_ComponentWidths` | stub turbine, line, tower, nacelle, each with its own kernel width | `RunOpenFASTADM.cmake`, `RunRestartParity.cmake`, `RunRestartAbort.cmake` | plotfile, flow log, `fx == -load_x`; restart parity; a changed `epsilon_tower` stops a restart (`OpenFAST_ALM_Tower_ExplicitWidths`, `RunOptionParity.cmake`: widths given equal to `epsilon` change nothing) |
| `OpenFAST_ALM_FLLC` | stub turbine, line, lifting-line correction | `RunOpenFASTADM.cmake` | the correction log |
| `OpenFAST_ALM_FLLC_Restart` | as above | `RunRestartParity.cmake` | restart parity of the correction and every log |
| `OpenFAST_ALM_FLLC_Automatic` | stub turbine, line, `fllc = automatic`, 20 steps | `RunOptionParity.cmake`, `RunRestartParity.cmake` | automatic equals the same settings given by hand (zero tolerance); restart parity with the width set again from the restored rotor |
| `OpenFAST_ADM_Askervein` | IEA 15 MW, **real OpenFAST**, disk, on the Askervein summit | `RunOpenFASTADM.cmake` | plotfile, flow and turbine logs (1e-6, six digits), `fx == -(T.n) n_x` (`Tests/check_openfast_shaft_source.py`) |
| `OpenFAST_ALM_Askervein` | IEA 15 MW, **real OpenFAST**, line with FLLC, tower and nacelle, on the Askervein summit | `RunOpenFASTADM.cmake` | plotfile, flow and turbine logs (1e-6, six digits), `fx == -load_x` |

Each case also has a box-parity twin registered next to it (one box on one
rank against a split domain on several ranks) where the feature adds a
decomposition-sensitive step.

The start-up checks have one abort test each (`add_test_abort`, label
`moving-bodies`), run on the decks above with one input changed: an anchor
level above the finest or missing at the start, a stop time that is not a
whole number of steps (of the single level, and of level 0 of two), a
prescribed-Ct disk's `air_density` off ERF's density, a finer level over the
bodies, floating-point traps with a turbine, an out-of-range
`correction_relax`, an actuator-line tip that sweeps more cells per step
than `alm_max_tip_cells` allows (on a flat mesh, over a ridge where the physical cells are shorter, and on a
stretched mesh where the short cells near the ground count with the share of the tip speed that crosses them), a nacelle kernel too narrow for its drag area (correction factor under 0.5),
a tower width given without a tower, and two turbines of different OpenFAST time steps on one rank
(`MovingBodies_MixedTimeSteps_OneRank`). `MovingBodies_Owners_*` and `MovingBodies_MixedTimeSteps_TwoRanks`
run a deck for one step on two ranks and require it to end normally with the turbines and disks on the ranks the
restart and box-parity tests rely on (and the ranks their points and wake lines reach), and turbines of different OpenFAST time steps on different ranks
(`Tests/RunExpectExit.cmake`). `OpenFAST_ADM_TwoTurbines/stub_turbine_dt002.fst` is the stub deck with
`dt = 0.02` those tests give the second turbine. `MovingBodies_StopDatetime` runs `OpenFAST_ADM_Restart` to
a `stop_datetime` past the deck's `stop_time` and requires it to get there.

The decks that do not set `sampling` run the default `disk_corrected`; on the
50 m decks its filter width is about two rotor radii, past the range the factor
was fitted for, which is fine for a regression of the feature each deck tests.
`OpenFAST_ADM_DiskCorrected` is the set-up inside that range.

## Rules

- The stub turbine file (`stub_turbine.fst`) is the bundled stub's `key = value`
  deck, not an OpenFAST model; the start-up audit skips the model-file checks
  for it and says so.
- A gold log is the run's own output copied from a two-rank run; regenerate
  it only when the physics changes, and say why in the pull request.
- New cases go here with a row in this table and an entry in
  `Docs/sphinx_doc/RegressionTests.rst`.
- `OpenFAST_IEA15_PowerCurve` is an example, not a regression case: the IEA 15 MW turbine with the ROSCO
  controller and the real OpenFAST library on a flat domain with one to three levels, as a disk and as a
  line, compared with OpenFAST alone at five wind speeds (see its README). It needs the ROSCO library
  (`Build/setup_rosco.sh`, or `-DERF_BUILD_ROSCO=ON`) and its runs take a quarter of an hour to an hour. With
  `ROSCO_DIR` or `ERF_BUILD_ROSCO=ON` four ten-step tests are registered (label `rosco`,
  `Tests/RunIEA15PowerCurve.cmake`), one per deck: `OpenFAST_IEA15_PowerCurve_adm_20m`, `_adm_10m`, `_alm_10m` and
  `_alm_5m` make their run folder with the case's `prepare.py`, require that ServoDyn loaded ROSCO, and compare rotor speed,
  thrust, torque and power in `T1_erf.csv` with `gold/<deck>_T1_erf.csv.gold` to six digits.
- `ScalingFarm` is not a case: it holds the tools that write and time farms of
  16 to 1024+ stub turbines (see its README); nothing in it is registered with CTest.
