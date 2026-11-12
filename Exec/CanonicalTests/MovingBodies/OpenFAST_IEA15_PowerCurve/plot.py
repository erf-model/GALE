#!/usr/bin/env python3
"""Compare the coupled runs of this case with stand-alone OpenFAST.

    python3 plot.py                # your runs under runs/, against the reference table
    python3 plot.py --reference    # the reference table alone (remakes erf_vs_openfast.png)

For every runs/<deck>/ws<speed> folder that ran to 360 s, the script averages generator
power, rotor speed, torque, thrust and blade pitch over 300-360 s from the OpenFAST output
file. Stand-alone OpenFAST runs under runs/standalone are averaged over 120-700 s; where
there are none, the stand-alone values of reference.csv are used. It writes
runs/means.csv and runs/erf_vs_openfast.png, and prints the differences in power and thrust.
"""
import argparse
import csv
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
VARS = ["GenPwr", "RotSpeed", "RotTorq", "RotThrust", "BldPitch1"]
CASES = [  # name, label, colour, marker, OpenFAST primary file of the run
    ("adm_20m", "Disk, RANS, 20 m (one level)", "#2a78d6", "s", "IEA15-land-bem"),
    ("adm_10m", "Disk, RANS, 10 m (two levels)", "#8a5cd6", "^", "IEA15-land-bem"),
    ("alm_10m", "Line + FLLC, 10 m (two levels)", "#eb6834", "o", "IEA15-land"),
    ("alm_5m", "Line + FLLC, 5 m (three levels)", "#1baf7a", "D", "IEA15-land"),
]
PANELS = [("GenPwr", "Power (MW)", 1e-3), ("RotThrust", "Rotor thrust (MN)", 1e-3),
          ("BldPitch1", "Blade pitch (deg)", 1.0)]


def window_mean(path, t0, t1):
    """Means of VARS over t0 <= Time <= t1 of an OpenFAST text output file; None if it stops before t1."""
    with open(path, errors="replace") as f:
        for line in f:
            if line.startswith("Time"):
                names = line.split()
                break
        else:
            return None
        cols = [names.index(v) for v in VARS]
        next(f)   # units
        total, n, last = [0.0] * len(VARS), 0, None
        for line in f:
            p = line.split()
            if len(p) < len(names):
                continue
            t = float(p[0])
            if t == last:
                continue
            last = t
            if t0 <= t <= t1:
                n += 1
                for i, c in enumerate(cols):
                    total[i] += float(p[c])
    if n == 0 or last is None or last < t1 - 1e-6:
        return None
    return {v: s / n for v, s in zip(VARS, total)}


def read_table(path):
    out = {}
    with open(path) as f:
        for row in csv.DictReader(line for line in f if not line.startswith("#")):
            out[(row["case"], float(row["wind_speed"]))] = {v: float(row[v]) for v in VARS}
    return out


def from_runs(runs):
    out = {}
    for name, root, t0, t1 in [("standalone", "IEA15-land", 120.0, 700.0)] + \
                              [(c[0], c[4], 300.0, 360.0) for c in CASES]:
        for d in sorted(glob.glob(os.path.join(runs, name, "ws*"))):
            f = os.path.join(d, root + ".out")
            m = window_mean(f, t0, t1) if os.path.exists(f) else None
            if m is None:
                print(f"skipped {d}: no output up to {t1:g} s")
            else:
                out[(name, float(os.path.basename(d)[2:]))] = m
    return out


def figure(data, path, title):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    ink, muted, grid = "#0b0b0b", "#52514e", "#e4e3df"
    plt.rcParams.update({"font.size": 10, "axes.edgecolor": muted, "axes.labelcolor": ink,
                         "xtick.color": muted, "ytick.color": muted,
                         "axes.spines.top": False, "axes.spines.right": False})
    speeds = sorted(ws for (c, ws) in data if c == "standalone")
    fig, ax = plt.subplots(2, 3, figsize=(13, 7.2), sharex=True)
    for j, (v, ylab, sc) in enumerate(PANELS):
        a, e = ax[0, j], ax[1, j]
        a.plot(speeds, [data[("standalone", ws)][v] * sc for ws in speeds], color=ink, lw=2,
               label="OpenFAST alone", zorder=2)
        for name, lab, col, mk, _ in CASES:
            ws_c = [ws for ws in speeds if (name, ws) in data]
            if not ws_c:
                continue
            y = [data[(name, ws)][v] for ws in ws_c]
            ref = [data[("standalone", ws)][v] for ws in ws_c]
            d = [yy - rr if v == "BldPitch1" else 100 * (yy / rr - 1) for yy, rr in zip(y, ref)]
            a.plot(ws_c, [yy * sc for yy in y], ls="none", marker=mk, ms=8, mfc=col, mec="white",
                   mew=1.5, label=lab, zorder=3)
            e.plot(ws_c, d, color=col, lw=2, marker=mk, ms=8, mec="white", mew=1.5, zorder=3)
        a.set_ylabel(ylab)
        e.axhline(0, color=ink, lw=1)
        e.set_ylabel("Coupled - OpenFAST (deg)" if v == "BldPitch1" else "Difference from OpenFAST (%)")
        e.set_xlabel("Wind speed (m/s)")
        e.set_xticks(speeds)
        if v != "BldPitch1":
            e.axhspan(-5, 5, color="#eeeeea", zorder=0)
            e.set_ylim(-8, 8)
        for x in (a, e):
            x.grid(color=grid, lw=1)
            x.set_axisbelow(True)
            x.axvline(10.59, color=muted, lw=1, ls=":")
    h, l = ax[0, 0].get_legend_handles_labels()
    fig.legend(h, l, loc="upper center", ncol=len(h), frameon=False, bbox_to_anchor=(0.5, 0.95))
    fig.suptitle(title, fontsize=13)
    fig.text(0.5, 0.01, "Means over 300-360 s (OpenFAST alone: 120-700 s). Dotted line: rated wind speed, "
             "10.59 m/s. Shaded band: +/- 5 %.", ha="center", color=muted, fontsize=9)
    fig.tight_layout(rect=(0, 0.03, 1, 0.9))
    fig.savefig(path, dpi=150)
    print("wrote", path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--reference", action="store_true", help="plot reference.csv alone")
    ap.add_argument("--runs", default=os.path.join(HERE, "runs"))
    a = ap.parse_args()

    ref = read_table(os.path.join(HERE, "reference.csv"))
    title = "IEA 15 MW with ROSCO in a uniform wind: coupled runs and OpenFAST alone"
    if a.reference:
        figure(ref, os.path.join(HERE, "erf_vs_openfast.png"), title)
        return
    data = from_runs(a.runs)
    if not any(c != "standalone" for (c, _) in data):
        sys.exit(f"plot.py: no finished coupled run under {a.runs}")
    for key, val in ref.items():
        if key[0] == "standalone":
            data.setdefault(key, val)
    with open(os.path.join(a.runs, "means.csv"), "w") as f:
        f.write("case,wind_speed," + ",".join(VARS) + "\n")
        for (c, ws) in sorted(data):
            f.write(f"{c},{ws}," + ",".join(f"{data[(c, ws)][v]:.6g}" for v in VARS) + "\n")
    print(f"{'case':10s} {'U':>5s} {'power %':>9s} {'thrust %':>9s} {'pitch deg':>10s}   (reference table)")
    for (c, ws) in sorted(data):
        if c == "standalone" or ("standalone", ws) not in data:
            continue
        o = data[("standalone", ws)]

        def diffs(m):
            return (100 * (m["GenPwr"] / o["GenPwr"] - 1), 100 * (m["RotThrust"] / o["RotThrust"] - 1),
                    m["BldPitch1"] - o["BldPitch1"])
        line = f"{c:10s} {ws:5.1f} " + "{:9.2f} {:9.2f} {:10.3f}".format(*diffs(data[(c, ws)]))
        if (c, ws) in ref and ("standalone", ws) in ref:
            o = ref[("standalone", ws)]
            line += "   ({:.2f} {:.2f} {:.3f})".format(*diffs(ref[(c, ws)]))
        print(line)
    figure(data, os.path.join(a.runs, "erf_vs_openfast.png"), title)


if __name__ == "__main__":
    main()
