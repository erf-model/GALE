# Actuator_TurbineCtDisk

## Purpose

Two prescribed actuator disks side by side in a uniform 10.25 m/s anelastic flow.
`T1` names the turbine table `NREL_5MW_126` of GALE's turbine library, so its
rotor radius (63 m), hub height (90 m), thrust coefficient Ct(U) and power curve
P(U) come from the table. `D1` is a constant-Ct disk of the same size (Ct = 0.75).
In every row, T1's Ct must be the table's Ct at its sampled free-stream speed, and
both thrusts must be 1/2 rho Ct U|U| pi R^2. Over the run T1's free-stream speed
falls from 10.25 to 10.19 m/s, across the table row at 10.2 m/s.

## Files

| file | what it is |
| --- | --- |
| `Actuator_TurbineCtDisk.i` | the deck: 50 m cells, 10 steps of 0.5 s, the disks at y = 300 and 900 m |
| `check_turbine_disk.py` | reads the turbine table itself and checks the two disk logs against it and the thrust law |
| `T1_disk.csv.gold`, `D1_disk.csv.gold` | the disk logs of the run (10 significant digits) |

## Data

The NREL 5 MW table, `Turbines/Data/PowerCurves/NREL_5MW_126.txt`, from the NREL
turbine-models archive (see the next section). Nothing needs to be downloaded.

## Data and acknowledgements

The NREL 5 MW curve comes from the NREL turbine-models archive,
<https://github.com/NatLabRockies/turbine-models> (BSD 3-Clause, Copyright (c) 2020,
Alliance for Sustainable Energy, LLC). The turbine is documented in Jonkman,
Butterfield, Musial and Scott, *Definition of a 5-MW Reference Wind Turbine for
Offshore System Development*, NREL/TP-500-38060 (2009). We thank NREL for making the
archive openly available. The table is redistributed in
`Turbines/Data/PowerCurves`, whose README carries the licence text.

## How to run

```
mpiexec -n 2 erf_exec Actuator_TurbineCtDisk.i
python3 check_turbine_disk.py T1_disk.csv <GALE>/Turbines/Data/PowerCurves/NREL_5MW_126.txt D1_disk.csv 0.75 1.0
```

## Expected Results

Both logs have the columns `u_inf,u_disk,thrust,power,spread_thrust,ct,power_curve`.
T1's `ct` runs from 0.78226 to 0.78336, the table's values at its free-stream speed,
and `power_curve` is the table's power (3.71 MW at 10.25 m/s). D1's `ct` is 0.75
and its `power_curve` equals `power` (T U_d). The checker agrees to 1e-7 relative in
every row. `spread_thrust` is the force actually spread onto the grid, summed over both
disks, so it is the same in the two logs.

## CTest

`Actuator_TurbineCtDisk` (`Tests/RunTurbineCtDisk.cmake`), label `moving-bodies`:
the two logs against their golds, then `check_turbine_disk.py`. Needs MPI, FFT and
Python 3.
