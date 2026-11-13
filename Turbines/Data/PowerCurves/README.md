# GALE turbine library

## Purpose

Thrust-coefficient and power curves of published wind turbines, for the prescribed
actuator disk (`type = ct_disk`). A disk given

```
erf.moving_bodies.T1.type    = ct_disk
erf.moving_bodies.T1.turbine = NREL_5MW_126
```

reads `NREL_5MW_126.txt` from this folder (or from `erf.moving_bodies.turbine_data_dir`)
and takes its thrust coefficient Ct(U) at the sampled free-stream speed, its rotor radius
(half the table's diameter) and, when the table gives one, its hub height. See the
"Prescribed uniform-Ct disk" section of the moving-bodies theory page.

## Files

| file | what it is |
| --- | --- |
| `<name>.txt` | one turbine's table (44 tables, listed below) |
| `make_power_curves.py` | downloads the sources and writes the tables |

Each table holds `#` comments (name, source, licence), the keys `rotor_diameter` (m),
`rated_power` (kW) and, when the turbine has one hub height, `hub_height` (m), then one row
per wind speed: wind speed (m/s), Ct (-), electrical power (kW). Wind speeds increase
strictly. Between rows the code interpolates linearly; below the first and above the last
speed Ct and power are zero. Only rows with Ct > 0 are kept: the script drops the zero-Ct
rows some sources list below cut-in (15 tables) and the three zero-Ct rows between non-zero
ones in the Eno 114 source (20, 22 and 24 m/s), so the thrust neither ramps up from zero
below cut-in nor drops to zero and back above rated. Where a turbine is offered at several hub heights the table
lists them in a comment; there, and for the six tables whose source gives no hub height, the deck must give `hub_height`.

Only turbines with a published Ct curve are included. Ct derived from a power curve with
ideal momentum theory came out 29 to 34 % below the published Ct at peak Cp for the eight
NREL, IEA, DTU and LEANWIND reference tables (25 to 37 % over all 44), so power-only
turbines are left out.

The curves are for sea-level density, 1.225 kg/m^3, as published. Ct may exceed 1 near
cut-in (NREL 5 MW: 1.13 at 3 m/s); the reader accepts 0 <= Ct <= 2.
Two tables reach a power above their rated power, as published: `DTU_10MW_178` up to
10684 kW (rated 10000 kW) and `Vestas_V112_3000` up to 3075 kW (rated 3000 kW).

### NREL turbine-models archive

| name (`turbine =`) | D (m) | hub (m) | rated (kW) | U (m/s) | source file |
| --- | --- | --- | --- | --- | --- |
| `DTU_10MW_178` | 178.3 | 119 | 10000 | 4 to 25 | Offshore/DTU_Reference_v1_10MW_178.csv |
| `LEANWIND_8MW_164` | 164 | 110 | 8000 | 4 to 25 | Offshore/LEANWIND_Reference_8MW_164.csv |
| `NREL_5MW_126` | 126 | 90 | 5000 | 3 to 25 | Offshore/NREL_Reference_5MW_126.csv |
| `NREL_Bespoke_6MW_170` | 170 | 115 | 6000 | 3 to 25 | Onshore/2023NREL_Bespoke_6MW_170.csv |
| `Vestas_V82_1.65MW` | 82 | 59, 68.5, 70, 78, 80 (choose) | 1650 | 3 to 20 | Onshore/VestasV82_1.65MW_82.csv |

### IEA Wind Task 37 reference turbines

Ct and electrical power from the CCBlade performance tables (3.4 MW, 10 MW) and the
"Rotor Performance" sheets of the tabular documentation (15 MW; 22 MW: the WISDEM sheet,
whose thrust is in N; the HAWC2 and OpenFAST sheets label N as kN).

| name (`turbine =`) | D (m) | hub (m) | rated (kW) | U (m/s) | source file |
| --- | --- | --- | --- | --- | --- |
| `IEA_10MW_198` | 198 | 119 | 10000 | 4 to 25 | IEA-10.0-198-RWT, performance/performance_ccblade.dat |
| `IEA_15MW_240` | 241.351 | 150 | 15000.1 | 3 to 25 | IEA-15-240-RWT, Documentation/IEA-15-240-RWT_tabular.xlsx, sheet 'Rotor Performance' |
| `IEA_22MW_280` | 284 | 170 | 22000.4 | 3 to 25 | IEA-22-280-RWT, Documentation/IEA-22-280-RWT_tabular.xlsx, sheet 'Rotor Performance - WISDEM' |
| `IEA_3.4MW_130` | 130 | 110 | 3370 | 3 to 25 | IEA-3.4-130-RWT, performance/performance_ccblade.dat |

### OpenEnergy database (OEDB) wind turbine library

Every OEDB turbine with a Ct curve (manufacturers Eno, GE, Nordex, Senvion, Siemens, Vestas).
Each table's header names the database's own source for that turbine.

| name (`turbine =`) | D (m) | hub (m) | rated (kW) | U (m/s) | OEDB turbine_type, id |
| --- | --- | --- | --- | --- | --- |
| `Eno_ENO100_2200` | 100 | 99 | 2200 | 3 to 25 | ENO100/2200, id 128 |
| `Eno_ENO114_3500` | 114 | 92, 127.5, 142 (choose) | 3500 | 3 to 25 | ENO114/3500, id 127 |
| `Eno_ENO126_3500` | 126 | 117, 137, 165 (choose) | 3500 | 3 to 25 | ENO126/3500, id 124 |
| `GE_GE103_2750` | 103 | 75, 85, 98.3, 123.5 (choose) | 2750 | 3 to 25 | GE103/2750, id 117 |
| `GE_GE120_2500` | 120 | 110, 139 (choose) | 2500 | 3 to 20 | GE120/2500, id 119 |
| `GE_GE120_2750` | 120 | 85, 98.3, 110, 139 (choose) | 2750 | 3 to 25 | GE120/2750, id 116 |
| `GE_GE130_3200` | 130 | 85, 110, 134, 155 (choose) | 3200 | 3 to 25 | GE130/3200, id 114 |
| `Nordex_N100_2500` | 100 | 75, 85, 100 (choose) | 2500 | 3 to 25 | N100/2500, id 22 |
| `Nordex_N117_2400` | 117 | 91, 120, 141 (choose) | 2400 | 3 to 20 | N117/2400, id 20 |
| `Nordex_N131_3000` | 131 | 99, 114, 134 (choose) | 3000 | 3 to 20 | N131/3000, id 17 |
| `Nordex_N131_3300` | 131 | 134, 164 (choose) | 3300 | 3 to 20 | N131/3300, id 16 |
| `Nordex_N131_3600` | 131 | 84, 106, 112, 134 (choose) | 3600 | 3 to 20 | N131/3600, id 15 |
| `Nordex_N90_2500` | 90 | 65, 70, 80 (choose) | 2500 | 3 to 26 | N90/2500, id 23 |
| `Senvion_MM100_2000` | 100 | give hub_height | 2000 | 3 to 22 | MM100/2000, id 96 |
| `Senvion_S114_3400` | 114 | 93, 119, 123, 143 (choose) | 3400 | 3 to 22 | S114/3400, id 89 |
| `Senvion_S122_3000` | 122 | 136, 139 (choose) | 3000 | 3 to 22 | S122/3000, id 95 |
| `Senvion_S122_3200` | 122 | 139 | 3200 | 3 to 22 | S122/3200, id 94 |
| `Siemens_SWT113_2300` | 113 | 99.5 | 2300 | 3 to 25 | SWT113/2300, id 73 |
| `Siemens_SWT113_3200` | 113 | 79.5, 92.5, 99.5, 122, 142 (choose) | 3200 | 3 to 25 | SWT113/3200, id 64 |
| `Siemens_SWT120_3600` | 120 | 90 | 3600 | 4 to 25 | SWT120/3600, id 61 |
| `Siemens_SWT130_3300` | 130 | 85, 110, 120, 135 (choose) | 3300 | 3 to 25 | SWT130/3300, id 63 |
| `Siemens_SWT130_3600` | 130 | 85, 115, 135, 165 (choose) | 3600 | 3 to 25 | SWT130/3600, id 60 |
| `Siemens_SWT142_3150` | 142 | 109, 129, 165 (choose) | 3150 | 3 to 23 | SWT142/3150, id 67 |
| `Vestas_V100_1800` | 100 | give hub_height | 1800 | 3 to 20 | V100/1800, id 134 |
| `Vestas_V100_1800_GS` | 100 | give hub_height | 1800 | 3 to 20 | V100/1800/GS, id 135 |
| `Vestas_V112_3000` | 112 | give hub_height | 3000 | 3 to 25 | V112/3000, id 52 |
| `Vestas_V112_3075` | 112 | 84, 94, 119 (choose) | 3075 | 3 to 25 | V112/3075, id 51 |
| `Vestas_V112_3300` | 112 | 84, 94, 119, 140 (choose) | 3300 | 3 to 25 | V112/3300, id 50 |
| `Vestas_V112_3450` | 112 | 84 | 3450 | 3 to 25 | V112/3450, id 49 |
| `Vestas_V117_3450` | 117 | 91.5, 116.5, 141.5 (choose) | 3450 | 3 to 25 | V117/3450, id 47 |
| `Vestas_V117_3600` | 117 | give hub_height | 3600 | 3 to 25 | V117/3600, id 136 |
| `Vestas_V126_3000` | 126 | 119 | 3000 | 3 to 22.5 | V126/3000, id 44 |
| `Vestas_V126_3300` | 126 | 117, 137 (choose) | 3300 | 3 to 22.5 | V126/3300, id 43 |
| `Vestas_V126_3450` | 126 | 117, 137, 147, 149 (choose) | 3450 | 3 to 22.5 | V126/3450, id 42 |
| `Vestas_V90_2000_GS` | 90 | give hub_height | 2000 | 4 to 25 | V90/2000/GS, id 133 |

## Data and acknowledgements

We thank the providers of these data for making them openly available.

- **NREL turbine-models archive**, National Renewable Energy Laboratory,
  <https://github.com/NatLabRockies/turbine-models>. BSD 3-Clause licence,
  Copyright (c) 2020, Alliance for Sustainable Energy, LLC (licence text below, copied from the archive's LICENSE.txt).
  Redistributed here: the five tables of the first list, reformatted.
  The NREL 5 MW turbine is documented in Jonkman, Butterfield, Musial and Scott,
  *Definition of a 5-MW Reference Wind Turbine for Offshore System Development*,
  NREL/TP-500-38060 (2009).
- **IEA Wind Task 37 reference wind turbines**, IEA Wind TCP Task 37,
  <https://github.com/IEAWindSystems> (repositories IEA-3.4-130-RWT, IEA-10.0-198-RWT,
  IEA-15-240-RWT, IEA-22-280-RWT). Apache License 2.0
  (<https://www.apache.org/licenses/LICENSE-2.0>). Redistributed here: the four tables of
  the second list, columns extracted and reformatted (a change under section 4 of the
  licence). The turbines are documented in Bortolotti et al., *IEA Wind TCP Task 37:
  Systems Engineering in Wind Energy - WP2.1 Reference Wind Turbines*, NREL/TP-5000-73492
  (2019), Gaertner et al., *Definition of the IEA 15-Megawatt Offshore Reference Wind
  Turbine*, NREL/TP-5000-75698 (2020), and the IEA-22-280-RWT repository documentation.
- **OEDB wind turbine library** (supply.wind_turbine_library), Open Energy Family,
  maintained by the Reiner Lemoine Institut, <https://openenergyplatform.org>, as also used
  by windpowerlib. Open Database License 1.0
  (<https://opendatacommons.org/licenses/odbl/1.0/>). Contains information from the OEDB
  wind turbine library, which is made available here under the Open Database License
  (ODbL). Redistributed here: the 35 tables of the third list, a derived database
  (reformatted, one file per turbine), offered under the same licence. Each table's header
  names its own source as given in the OEDB.

Nothing needs to be downloaded to use the tables. `make_power_curves.py` downloads the
sources again only to regenerate them.

### NREL archive licence (BSD 3-Clause)

```
BSD 3-Clause License

Copyright (c) 2020, Alliance for Sustainable Energy, LLC
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## How to run

```
python3 make_power_curves.py <download cache folder> [<output folder>]
```

writes the tables into the output folder (default: this folder).

## Expected Results

The 44 tables above, identical to the committed ones while the sources are unchanged.

## CTest

`Actuator_TurbineCtDisk` (Exec/CanonicalTests/MovingBodies/Actuator_TurbineCtDisk) runs a
disk on `NREL_5MW_126`; the unit tests `TurbinePowerCurve.*` read `NREL_5MW_126` and
`Vestas_V82_1.65MW`.
