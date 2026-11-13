#!/usr/bin/env python3
"""Check the disk logs of Actuator_TurbineCtDisk against the turbine table and the thrust law.

Usage: check_turbine_disk.py <T1_disk.csv> <turbine table .txt> <D1_disk.csv> <D1 Ct> <rho>

The table is read here independently of ERF (keys rotor_diameter, hub_height, rated_power, then
rows "U Ct P_kW"), and Ct(U), P(U) interpolated linearly. In every row of T1's log the ct column
must equal the table's Ct at u_inf, power_curve the table's P(u_inf) in W, and thrust
1/2 rho ct u_inf |u_inf| pi (D/2)^2; in D1's log ct must be the constant Ct, the thrust the same law with
it, and power_curve the disk power thrust * u_disk. All to 1e-7 relative. Exits 1 on a mismatch.
"""
import bisect
import csv
import math
import sys

TOL = 1.0e-7


def read_table(path):
    keys, rows = {}, []
    with open(path) as f:
        for line in f:
            s = line.split("#", 1)[0].split()
            if not s:
                continue
            if s[0] in ("rotor_diameter", "hub_height", "rated_power"):
                keys[s[0]] = float(s[1])
            else:
                rows.append(tuple(float(v) for v in s))
    return keys, rows


def interp(rows, col, u):
    us = [r[0] for r in rows]
    if not (us[0] <= u <= us[-1]):
        return 0.0
    j = min(bisect.bisect_right(us, u), len(us) - 1)
    i = j - 1
    w = (u - us[i]) / (us[j] - us[i])
    return rows[i][col] + w * (rows[j][col] - rows[i][col])


def close(a, b, what, row, ok):
    if abs(a - b) > TOL * max(abs(b), 1.0):
        print(f"row {row}: {what}: log {a!r}, expected {b!r}")
        return False
    return ok


def read_log(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    if len(rows) < 3:
        sys.exit(f"check_turbine_disk.py: {path} has {len(rows)} rows; the check would be trivial")
    for c in ("u_inf", "u_disk", "thrust", "power", "ct", "power_curve"):
        if c not in rows[0]:
            sys.exit(f"check_turbine_disk.py: {path} has no column {c}")
    return rows


def main():
    t1, (keys, table), d1 = read_log(sys.argv[1]), read_table(sys.argv[2]), read_log(sys.argv[3])
    ct_d1, rho = float(sys.argv[4]), float(sys.argv[5])
    area = math.pi * (0.5 * keys["rotor_diameter"]) ** 2
    ok, cts = True, []
    for k, r in enumerate(t1, 1):
        u = float(r["u_inf"])
        ct = interp(table, 1, u)
        if ct <= 0.0:
            sys.exit(f"check_turbine_disk.py: T1 row {k}: u_inf = {u} lies outside the table; the check would be trivial")
        cts.append(ct)
        ok = close(float(r["ct"]), ct, "T1 ct vs table Ct(u_inf)", k, ok)
        ok = close(float(r["power_curve"]), 1000.0 * interp(table, 2, u), "T1 power_curve vs table P(u_inf)", k, ok)
        ok = close(float(r["thrust"]), 0.5 * rho * ct * u * abs(u) * area, "T1 thrust vs 1/2 rho Ct U|U| A", k, ok)
    if max(cts) - min(cts) <= 0.0:
        sys.exit("check_turbine_disk.py: T1's Ct never changed; the run does not exercise Ct(U)")
    for k, r in enumerate(d1, 1):
        u = float(r["u_inf"])
        ok = close(float(r["ct"]), ct_d1, "D1 ct vs its constant", k, ok)
        ok = close(float(r["thrust"]), 0.5 * rho * ct_d1 * u * abs(u) * area, "D1 thrust vs 1/2 rho Ct U|U| A", k, ok)
        ok = close(float(r["power_curve"]), float(r["thrust"]) * float(r["u_disk"]), "D1 power_curve vs T u_disk", k, ok)
    print(f"T1: {len(t1)} rows, Ct {min(cts):.6f} to {max(cts):.6f} from the table; D1: {len(d1)} rows at Ct {ct_d1}"
          + ("" if ok else "; MISMATCH"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
