# IEA 15 MW power curve: disk and line against OpenFAST alone

## Purpose

An example that runs with the real OpenFAST library on a flat domain, with refinement
levels. The IEA 15 MW turbine stands in a uniform wind under its ROSCO controller, at five
wind speeds from 5 to 14 m/s. The coupled runs are compared with OpenFAST run on its own in
the same wind. Below the rated wind speed (10.59 m/s) the power shows whether the rotor
sees the right wind; above it the controller holds the power, so the thrust and the blade
pitch are the measures.

It is an example, not a regression test: a run takes from a quarter of an hour to an hour
on four ranks, and it needs the ROSCO controller library, which the repository does not
hold. The short real-OpenFAST tests are `../OpenFAST_ADM_Askervein` and
`../OpenFAST_ALM_Askervein`.

## Files

| file | what it is |
| --- | --- |
| `adm_20m.i` | actuator disk, k-equation RANS, one level of 20 m cells |
| `adm_10m.i` | the same disk on two levels: 20 m, and 10 m around the rotor and the upstream sampling points |
| `alm_10m.i` | actuator line with the filtered lifting-line correction (FLLC), two levels: 20 m and 10 m |
| `alm_5m.i` | the same line on three levels: 20 m, 10 m and 5 m |
| `controller/` | the ROSCO controller inputs: `IEA15-land_ServoDyn.dat`, `IEA15-land_DISCON.IN`, `Cp_Ct_Cq.IEA15MW.txt` |
| `prepare.py` | makes one run folder per deck and wind speed, with the turbine model and the controller |
| `plot.py` | averages the runs, compares them with OpenFAST alone, writes a table and a figure |
| `reference.csv` | the averages of the runs described under Expected Results |
| `erf_vs_openfast.png` | the figure made from `reference.csv` (`python3 plot.py --reference`) |

The decks are written for 9 m/s; `prepare.py` sets the wind speed. All four share the
domain (2400 x 1920 x 1280 m, 20 m cells on level 0), the inflow and outflow boundaries in
x with no sponge, the anelastic solver with the implicit vertical solve, and a 0.2 s step
on level 0. The hub is at mid-height (z = 640 m), 600 m from the inflow.

| | `adm_20m.i` | `adm_10m.i` | `alm_10m.i` | `alm_5m.i` |
| --- | --- | --- | --- | --- |
| levels | 1 | 2 | 2 | 3 |
| finest cells | 20 m | 10 m | 10 m | 5 m |
| closure | k-equation RANS | k-equation RANS | none | none |
| ground | no-slip | no-slip | slip | slip |
| wind handed to OpenFAST | sampled 2 D upstream | sampled 2 D upstream | at the blade points | at the blade points |
| induction | OpenFAST (`Wake_Mod 1`) | OpenFAST (`Wake_Mod 1`) | resolved, with FLLC | resolved, with FLLC |
| kernel width | 40 m | 40 m | 8.4 m | 8.4 m |
| points per blade | 50 | 50 | 300 | 300 |

The line's kernel width is 0.035 rotor diameters, the bound of Sandia report
SAND2021-15447C, held at 8.4 m on both meshes. The line decks give the FLLC settings by hand;
`erf.moving_bodies.T1.fllc = automatic` sets the same values.

## Data and acknowledgements

**IEA Wind 15 MW reference turbine.** E. Gaertner et al., *Definition of the IEA Wind
15-Megawatt Offshore Reference Wind Turbine*, NREL/TP-5000-75698, 2020; model files from
https://github.com/IEAWindTask37/IEA-15-240-RWT, Apache License 2.0. We thank the IEA Wind
Task 37 authors for making the model and its controller tuning available.

- Redistributed in the repository: the land-based OpenFAST model in `../IEA15_land_model`
  (its README lists the source commit and every change), and here in `controller/`:
  - `IEA15-land_DISCON.IN`, from `OpenFAST/IEA-15-240-RWT-Monopile/IEA-15-240-RWT-Monopile_DISCON.IN`
    (its header says it was written with the ROSCO 2.10.1 tuning on 10/24/25). Two changes:
    `LoggingLevel` 1 -> 0, and `PerfFileName` names `IEA-15-240-RWT/Cp_Ct_Cq.IEA15MW.txt`.
  - `Cp_Ct_Cq.IEA15MW.txt`, from `OpenFAST/IEA-15-240-RWT`, with trailing blanks removed.
  - `IEA15-land_ServoDyn.dat`: the values of `IEA-15-240-RWT-Monopile_ServoDyn.dat` in the
    OpenFAST 5.0.0 file layout (the layout of the `5MW_Land_DLL_WTurb` ServoDyn file of the
    OpenFAST regression tests, Apache License 2.0). The pitch-actuator keys that layout adds
    keep its values and are unused. `DLL_FileName` is a placeholder that `prepare.py` fills.
- The source commit of the two controller files was not recorded when they were copied;
  the turbine model is from commit `e4993d63`.

**ROSCO controller.** NREL Reference OpenSource Controller,
https://github.com/NREL/ROSCO, Apache License 2.0, version 2.10.1. We thank the ROSCO
developers. The library is not redistributed: build it yourself (below).

**OpenFAST.** https://github.com/OpenFAST/openfast, Apache License 2.0, version 5.0.0. We
thank the OpenFAST developers for the external-inflow interface.

**Averaging windows.** The windows (300 to 360 s for the coupled runs, 120 to 700 s for
OpenFAST alone) and the five wind speeds follow the Kynema-SGF actuator-line calibration
by G. R. Yalla (`gyalla/ALM_Calibrations`, described in the Kynema-SGF calibration
walkthrough). We thank the author. No data from that work is redistributed here.

`reference.csv` and `erf_vs_openfast.png` are results of runs made for this case; they
contain no third-party data.

## How to run

1. Build OpenFAST 5.0.0 and GALE against it, as in the top-level README
   (`Build/setup_openfast.sh --no-cpp-api`, then `-DERF_ENABLE_OPENFAST=ON
   -DOPENFAST_DIR=<install prefix>` with MPI and FFT on).
2. Build the ROSCO 2.10.1 controller library (`libdiscon.so`, or `.dylib` on macOS)
   following the ROSCO documentation.
3. Make the run folders, here for one deck at one speed (leave the two options out for all
   four decks at all five speeds):

   ```bash
   python3 prepare.py --libdiscon /path/to/libdiscon.so --decks alm_10m --speeds 9.0
   ```

4. Run a deck from its folder:

   ```bash
   cd runs/alm_10m/ws9.0 && mpiexec -n 4 /path/to/erf_exec alm_10m.i
   ```

5. Compare with OpenFAST alone:

   ```bash
   python3 plot.py
   ```

   It prints the differences in power, thrust and pitch next to those of `reference.csv`,
   and writes `runs/means.csv` and `runs/erf_vs_openfast.png`.

The stand-alone values come from `reference.csv`. To run them again,
`python3 prepare.py --libdiscon ... --standalone` makes `runs/standalone/ws<speed>`; run
`openfast IEA15-land.fst` in each (700 s of turbine time) and `plot.py` uses them instead.

`prepare.py` copies `../IEA15_land_model` and makes these changes to the copy:

| file | change | why |
| --- | --- | --- |
| `IEA15-land.fst`, `IEA15-land-bem.fst` | `CompServo` 0 -> 1, `ServoFile` names `IEA15-land_ServoDyn.dat`, `TMax` 10000 | the controller runs; ERF sets the stop time |
| `IEA15-land_ElastoDyn.dat` | `GenDOF` True; `BlPitch(1..3)` and `RotSpeed` set for the wind speed | the controller needs a free rotor; starting near the operating point shortens the start-up |
| `IEA15-land_AeroDyn15.dat` | `TwrPotent`, `TwrShadow` 0 -> 1 | these decks put no tower drag on the flow, so AeroDyn keeps its tower influence |
| `IEA15-land_ServoDyn.dat` | `DLL_FileName` set to `--libdiscon` | |

The initial pitch and rotor speed are interpolated from the Rotor Performance sheet of the
turbine's tabular data (`Documentation/IEA-15-240-RWT_tabular.xlsx` of the source
repository) and are listed in `prepare.py`.

A run with an `openfast_turbine` needs the AMReX floating-point traps off, which is the
default.

## Expected Results

`reference.csv` holds the averages of runs made in November 2026 with OpenFAST 5.0.0 and
ROSCO 2.10.1 on four ranks. `erf_vs_openfast.png` shows them. Each entry below is the
difference from OpenFAST alone in power / thrust.

| U (m/s) | `adm_20m` | `alm_10m` | `alm_5m` |
| --- | --- | --- | --- |
| 5.0 | -0.2 % / -0.1 % | +1.4 % / +0.6 % | +3.7 % / +1.6 % |
| 6.5 | -0.2 % / -0.1 % | -1.1 % / -0.4 % | +1.3 % / +0.7 % |
| 9.0 | -0.2 % / -0.1 % | -3.8 % / -1.9 % | -1.1 % / -0.4 % |
| 11.0 | 0.0 % / +0.1 % | 0.0 % / +6.6 % | 0.0 % / +4.3 % |
| 14.0 | 0.0 % / 0.0 % | 0.0 % / +2.5 % | 0.0 % / +2.0 % |

- The disk stays within 0.2 % in power and thrust at every speed, and within 0.02 degree
  in pitch.
- The line stays within 5 % in power and thrust on both meshes, except the thrust at
  11 m/s on 10 m cells (+6.6 %). Above rated its pitch is 0.3 to 1.1 degree below
  OpenFAST's.
- The `adm_20m`, `alm_10m` and `alm_5m` rows were made with the GALE code as it was at
  hgopalan/ERF#553 and #554. Later code can differ in the last digits.

`adm_10m` has no row yet: the two-level disk is new with this case and its five runs are not in
`reference.csv`.

## CTest

None. The case is not registered with CTest: it needs the ROSCO library and its runs are
long. `prepare.py` and `plot.py --reference` need only Python 3 (and matplotlib for the
figure).
