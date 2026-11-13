#!/usr/bin/env python3
"""Write GALE's turbine power-curve tables (<name>.txt in this folder) from their open sources.

The tables are read by a ct_disk with erf.moving_bodies.<name>.turbine = <table name>. Three sources:

* NREL turbine-models archive, https://github.com/NatLabRockies/turbine-models (BSD-3-Clause,
  (c) 2020 Alliance for Sustainable Energy, LLC): the files with a thrust-coefficient column.
* IEA Wind Task 37 reference turbines, https://github.com/IEAWindSystems (Apache-2.0): the
  3.4, 10, 15 and 22 MW rotor-performance tables.
* OpenEnergy database (OEDB) wind turbine library, https://openenergyplatform.org (ODbL-1.0,
  (c) Reiner Lemoine Institut): the turbines with a thrust-coefficient curve.

Usage: python3 make_power_curves.py <download cache dir> [<output dir, default: this folder>]

Every table has '#' comment lines (name, source, licence), then the keys

    rotor_diameter <m>
    hub_height <m>          (only when the source gives one height)
    rated_power <kW>

and one row per wind speed: wind speed (m/s), thrust coefficient (-), electrical power (kW),
wind speeds strictly increasing. Only tables with a published thrust coefficient are written;
no thrust coefficient is derived from a power coefficient.
"""

import csv
import io
import json
import os
import sys
import urllib.request

NREL_RAW = "https://raw.githubusercontent.com/NatLabRockies/turbine-models/master/turbine_models/"
IEA_RAW = "https://raw.githubusercontent.com/IEAWindSystems/{repo}/{branch}/{path}"
OEDB_ROWS = "https://openenergyplatform.org/api/v0/schema/supply/tables/wind_turbine_library/rows/"

NREL_NOTE = ("NREL turbine-models archive, https://github.com/NatLabRockies/turbine-models",
             "BSD-3-Clause, (c) 2020 Alliance for Sustainable Energy, LLC")
IEA_LICENCE = "Apache-2.0, IEA Wind Task 37"
OEDB_NOTE = ("OpenEnergy database wind turbine library (supply.wind_turbine_library), "
             "https://openenergyplatform.org",
             "ODbL-1.0 (https://opendatacommons.org/licenses/odbl/1.0/), (c) Reiner Lemoine Institut")

# NREL archive files with a Ct column: table name -> (group, file stem). The IEA turbines are taken
# from the IEA repositories instead (newer curves); the Vestas V82 is the archive's.
NREL_FILES = {
    "NREL_5MW_126": ("Offshore", "NREL_Reference_5MW_126"),
    "DTU_10MW_178": ("Offshore", "DTU_Reference_v1_10MW_178"),
    "LEANWIND_8MW_164": ("Offshore", "LEANWIND_Reference_8MW_164"),
    "NREL_Bespoke_6MW_170": ("Onshore", "2023NREL_Bespoke_6MW_170"),
    "Vestas_V82_1.65MW": ("Onshore", "VestasV82_1.65MW_82"),
}

# IEA tables: name -> (repo, branch, path, NREL archive spec for D/hub/rated when the file has none)
IEA_FILES = {
    "IEA_3.4MW_130": ("IEA-3.4-130-RWT", "master", "performance/performance_ccblade.dat",
                      ("Onshore", "IEA_Reference_3.4MW_130")),
    "IEA_10MW_198": ("IEA-10.0-198-RWT", "master", "performance/performance_ccblade.dat",
                     ("Offshore", "IEA_Reference_10MW_198")),
    "IEA_15MW_240": ("IEA-15-240-RWT", "master", "Documentation/IEA-15-240-RWT_tabular.xlsx", None),
    "IEA_22MW_280": ("IEA-22-280-RWT", "main", "Documentation/IEA-22-280-RWT_tabular.xlsx", None),
}


def fetch(url, cache, name):
    """Download url into cache/name once; return the bytes."""
    path = os.path.join(cache, name)
    if not os.path.exists(path):
        with urllib.request.urlopen(url, timeout=120) as r:
            data = r.read()
        with open(path, "wb") as f:
            f.write(data)
    with open(path, "rb") as f:
        return f.read()


def nrel_spec(cache, group, stem):
    """The archive's spec YAML as a dict of the plain 'key: value' lines (comments dropped)."""
    text = fetch(NREL_RAW + "specs/%s/%s.yaml" % (group, stem), cache, "nrel_%s.yaml" % stem).decode()
    spec = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        v = v.split("#", 1)[0].strip().strip("'\"")
        if v:
            spec[k.strip()] = v
    return spec


def write_table(out, name, comments, diameter, hub, rated_kw, rows):
    # Keep only rows with Ct > 0. Leading zero-Ct rows (below cut-in) would make
    # Ct ramp up from zero where the published curve has none; interior zero-Ct
    # rows (Eno 114 at 20, 22 and 24 m/s) would make the thrust jump to zero
    # and back. Outside the table the reader gives zero anyway.
    rows = [(u, ct, p) for u, ct, p in rows if ct > 0.0]
    for i in range(1, len(rows)):
        if not rows[i][0] > rows[i - 1][0]:
            raise SystemExit("%s: wind speeds not strictly increasing at row %d" % (name, i))
    for u, ct, p in rows:
        if not (u >= 0.0 and 0.0 <= ct <= 2.0 and p >= 0.0):
            raise SystemExit("%s: row (%g, %g, %g) out of range" % (name, u, ct, p))
    with open(os.path.join(out, name + ".txt"), "w") as f:
        f.write("# %s\n" % name)
        for c in comments:
            f.write("# %s\n" % c)
        f.write("# Written by make_power_curves.py; columns: wind speed (m/s), Ct (-), electrical power (kW)\n")
        f.write("rotor_diameter %.10g\n" % diameter)
        if hub is not None:
            f.write("hub_height %.10g\n" % hub)
        f.write("rated_power %.10g\n" % rated_kw)
        for u, ct, p in rows:
            f.write("%.10g %.10g %.10g\n" % (u, ct, p))
    return len(rows)


def nrel_tables(cache, out):
    for name, (group, stem) in NREL_FILES.items():
        text = fetch(NREL_RAW + "data/%s/%s.csv" % (group, stem), cache, "nrel_%s.csv" % stem).decode("utf-8-sig")
        rd = list(csv.reader(io.StringIO(text)))
        head = [h.strip() for h in rd[0]]
        iu, ip, ic = head.index("Wind Speed [m/s]"), head.index("Power [kW]"), head.index("Ct [-]")
        rows = []
        for r in rd[1:]:
            if len(r) > max(iu, ip, ic) and r[iu].strip() and r[ic].strip():
                rows.append((float(r[iu]), float(r[ic]), float(r[ip])))
        spec = nrel_spec(cache, group, stem)
        hubs = [h.strip() for h in spec.get("hub_height", "").strip("[]").split(",") if h.strip()]
        hub = float(hubs[0]) if len(hubs) == 1 else None
        comments = ["source: %s, %s/%s.csv" % (NREL_NOTE[0], group, stem), "licence: %s" % NREL_NOTE[1]]
        if len(hubs) > 1:
            comments.append("hub heights offered: %s (give erf.moving_bodies.<name>.hub_height)" % ", ".join(hubs))
        n = write_table(out, name, comments,
                        float(spec["rotor_diameter"]), hub, float(spec["rated_power"]), rows)
        print("%-24s %3d rows (NREL archive %s)" % (name, n, stem))


def iea_xlsx_rows(data, sheet):
    import openpyxl  # only the IEA 15 and 22 MW tables need it
    wb = openpyxl.load_workbook(io.BytesIO(data), read_only=True, data_only=True)
    ws = wb[sheet]
    it = ws.iter_rows(values_only=True)
    head = [str(h) for h in next(it)]
    iu, ip, ic = head.index("Wind [m/s]"), head.index("Power [MW]"), head.index("Thrust Coefficient [-]")
    # numeric rows only: the 15 MW sheet ends with a text note
    rows = [(float(r[iu]), float(r[ic]), 1000.0 * float(r[ip])) for r in it
            if all(isinstance(r[j], (int, float)) for j in (iu, ip, ic))]
    over = {}
    for r in wb["Overview"].iter_rows(values_only=True):
        if r[0] is not None and r[1] is not None:
            over[str(r[0])] = r[1]
    return rows, over


def iea_tables(cache, out):
    for name, (repo, branch, path, spec_ref) in IEA_FILES.items():
        url = IEA_RAW.format(repo=repo, branch=branch, path=path)
        data = fetch(url, cache, "iea_%s_%s" % (repo, os.path.basename(path)))
        src = "source: https://github.com/IEAWindSystems/%s, %s" % (repo, path)
        if path.endswith(".dat"):
            # performance_ccblade.dat: wind speed, rpm, pitch, electrical power (W), aero power (W), thrust (N), ...,
            # thrust coefficient in column 11 (1-based)
            rows = []
            for line in data.decode().splitlines():
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                v = line.split()
                rows.append((float(v[0]), float(v[10]), float(v[3]) / 1000.0))
            spec = nrel_spec(cache, *spec_ref)
            d, hub, rated = float(spec["rotor_diameter"]), float(spec["hub_height"]), float(spec["rated_power"])
            extra = ["rotor_diameter, hub_height, rated_power: NREL turbine-models specs/%s/%s.yaml (%s)"
                     % (spec_ref[0], spec_ref[1], NREL_NOTE[1])]
        else:
            # the 22 MW workbook has three performance sheets; WISDEM's (the one the 15 MW workbook has) is used:
            # its HAWC2 and OpenFAST sheets label the thrust kN but hold newtons
            sheet = "Rotor Performance" if "15-240" in repo else "Rotor Performance - WISDEM"
            rows, over = iea_xlsx_rows(data, sheet)
            src += ", sheet '%s'" % sheet
            d, hub = float(over["Rotor diameter [m]"]), float(over["Hub height [m]"])
            rated = max(p for _, _, p in rows)
            extra = ["rotor_diameter, hub_height: sheet 'Overview'; rated_power: the table's largest power"]
        n = write_table(out, name, [src, "licence: %s" % IEA_LICENCE] + extra, d, hub, rated, rows)
        print("%-24s %3d rows (IEA %s)" % (name, n, repo))


def oedb_tables(cache, out):
    rows_all = json.loads(fetch(OEDB_ROWS, cache, "oedb_wind_turbine_library.json").decode())
    names = set()
    for t in rows_all:
        try:
            us = json.loads(t["thrust_coefficient_curve_wind_speeds"])
            cts = json.loads(t["thrust_coefficient_curve_values"])
            pus = json.loads(t["power_curve_wind_speeds"])
            ps = json.loads(t["power_curve_values"])
        except (TypeError, ValueError):
            continue
        if not us or not cts or t["manufacturer"] == "IEA":   # the IEA 15 MW comes from its own repository
            continue
        if pus != us:
            raise SystemExit("OEDB %s: power and thrust curves on different wind speeds" % t["turbine_type"])
        man = t["manufacturer"].split("/")[0].replace(" Wind", "").replace(" ", "")
        name = "%s_%s" % (man, t["turbine_type"].replace("/", "_"))
        if name in names:
            raise SystemExit("OEDB: two turbines named %s" % name)
        names.add(name)
        hubs = [h.strip().replace(",", ".") for h in str(t["hub_height"]).split(";")
                if h.strip() and h.strip() != "None"]   # some entries use a decimal comma
        hub = float(hubs[0]) if len(hubs) == 1 else None
        comments = ["source: %s, turbine_type %s (id %s); the database's own source: %s"
                    % (OEDB_NOTE[0], t["turbine_type"], t["id"], (t["source"] or "not given").strip()),
                    "licence: %s" % OEDB_NOTE[1],
                    "Contains information from the OEDB wind turbine library, made available under the ODbL."]
        if len(hubs) > 1:
            comments.append("hub heights offered: %s (give erf.moving_bodies.<name>.hub_height)" % ", ".join(hubs))
        n = write_table(out, name, comments, float(t["rotor_diameter"]), hub, float(t["nominal_power"]),
                        list(zip(map(float, us), map(float, cts), map(float, ps))))
        print("%-24s %3d rows (OEDB %s)" % (name, n, t["turbine_type"]))


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    cache = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.abspath(__file__))
    os.makedirs(cache, exist_ok=True)
    nrel_tables(cache, out)
    iea_tables(cache, out)
    oedb_tables(cache, out)


if __name__ == "__main__":
    main()
