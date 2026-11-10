#!/usr/bin/env python3
"""Compare the induction of a disk on one level and on two levels (Actuator_CtDisk_TwoLevel).

Usage: check_levels.py <one-level D1_disk.csv> <two-level D1_disk.csv> <free stream m/s> <tolerance>

Reads the last row of each log and requires, for the disk-averaged velocity u_disk and the
velocity sampled a quarter of a diameter upstream u_inf, that the two-level deficit U - u
matches the one-level deficit within the relative tolerance. Exits 1 with the numbers when not.
"""
import csv
import sys


def last_row(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    if len(rows) < 2:
        sys.exit(f"check_levels.py: {path} has fewer than two rows")
    return rows[-1]


def main():
    one, two = last_row(sys.argv[1]), last_row(sys.argv[2])
    U, tol = float(sys.argv[3]), float(sys.argv[4])
    ok = True
    for col in ("u_disk", "u_inf"):
        d1, d2 = U - float(one[col]), U - float(two[col])
        if d1 <= 0.0:
            sys.exit(f"check_levels.py: the one-level {col} = {one[col]} shows no induction; the check would be trivial")
        rel = abs(d2 - d1) / d1
        print(f"{col}: one level {float(one[col]):.4f}, two levels {float(two[col]):.4f}, "
              f"deficits {d1:.4f} / {d2:.4f} m/s, relative difference {rel:.3f} (tolerance {tol})")
        ok = ok and rel <= tol
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
