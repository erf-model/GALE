# Actuator_CtDisk_TwoLevel

## Purpose

A prescribed uniform-Ct disk (R = 120 m, hub 300 m, Ct = 0.75) in a uniform 10 m/s
anelastic flow, run on one level and on two. On two levels the disk lives on the
fine level, whose box is tight around it (0.8 R up and down stream). The coarse
level must carry the disk's force too, summed onto its faces from the fine level,
so that its pressure solve feels the disk and the induction reaches beyond the
fine box. The two runs' induction must agree.

## Files

| file | what it is |
| --- | --- |
| `Actuator_CtDisk_OneLevel.i` | the reference: one level of 25 m cells, kernel 1 cell (25 m) |
| `Actuator_CtDisk_TwoLevel.i` | the same disk on a 25 m level 0 and a 12.5 m level 1 over x 650..850, y 350..850, z 0..500 m, kernel 2 fine cells (25 m) |
| `check_levels.py` | compares the last rows of the two `D1_disk.csv` logs |

## Data

None: both decks start from a uniform flow.

## How to run

```
mpiexec -n 2 erf_exec Actuator_CtDisk_OneLevel.i    # in one directory
mpiexec -n 2 erf_exec Actuator_CtDisk_TwoLevel.i    # in another
python3 check_levels.py one/D1_disk.csv two/D1_disk.csv 10.0 0.1
```

## Expected Results

After 60 s, the velocity deficits 10 - u of the disk-averaged velocity (`u_disk`)
and of the velocity a quarter of a diameter upstream (`u_inf`) agree within 10 %.
Before the coarse levels carried the force, the two-level disk saw 9.15 m/s
instead of 8.48 m/s at the disk and 9.87 m/s instead of 9.31 m/s upstream
(deficits 44 % and 81 % smaller), with 12 % more thrust.

## CTest

`Actuator_CtDisk_TwoLevel` (`Tests/RunDiskLevels.cmake`), label `moving-bodies`;
needs `ERF_ENABLE_MOVING_BODIES`, `ERF_ENABLE_FFT`, MPI and Python 3.
