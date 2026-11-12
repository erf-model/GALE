#!/usr/bin/env python3
"""Make the run folders of the IEA 15 MW power-curve case.

Each run folder holds one deck at one wind speed and a copy of the OpenFAST model of
../IEA15_land_model with the ROSCO controller switched on:

    python3 prepare.py --libdiscon /path/to/libdiscon.so
    python3 prepare.py --libdiscon /path/to/libdiscon.so --decks alm_10m --speeds 9.0
    python3 prepare.py --libdiscon /path/to/libdiscon.so --standalone

The folders are written to runs/<deck>/ws<speed> (runs/standalone/ws<speed> for the
stand-alone OpenFAST reference). README.md lists every change made to the model files.
"""
import argparse
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "..", "IEA15_land_model")
CONTROLLER = os.path.join(HERE, "controller")
DECKS = ["adm_20m", "adm_10m", "alm_10m", "alm_5m"]

# Wind speed (m/s): initial blade pitch (deg) and rotor speed (rpm), interpolated from the
# "Rotor Performance" sheet of IEA-15-240-RWT_tabular.xlsx (IEA Wind Task 37), so that the
# controller settles within the first 120 s.
INITIAL = {
    5.0: (2.8989, 5.0000),
    6.5: (0.8534, 5.0000),
    9.0: (0.0000, 6.4097),
    11.0: (2.6508, 7.5176),
    14.0: (9.9804, 7.5176),
}


def setval(text, key, val):
    """Replace the value in front of an OpenFAST key (its first occurrence)."""
    pat = re.compile(r"^(\s*)(\"[^\"]*\"|\S+)(\s+" + re.escape(key) + r")(?=\s|$)", re.M)
    new, n = pat.subn(lambda m: m.group(1) + str(val) + m.group(3), text, count=1)
    if n != 1:
        sys.exit(f"prepare.py: key {key} not found")
    return new


def edit(path, changes):
    with open(path) as f:
        text = f.read()
    for key, val in changes:
        text = setval(text, key, val)
    with open(path, "w") as f:
        f.write(text)


def model_files(d, ws, libdiscon, standalone):
    """Copy the model into d and switch the controller on."""
    shutil.copytree(MODEL, d, ignore=shutil.ignore_patterns("README.md", "LICENSE"))
    shutil.copy(os.path.join(CONTROLLER, "IEA15-land_ServoDyn.dat"), d)
    shutil.copy(os.path.join(CONTROLLER, "IEA15-land_DISCON.IN"), d)
    shutil.copy(os.path.join(CONTROLLER, "Cp_Ct_Cq.IEA15MW.txt"), os.path.join(d, "IEA-15-240-RWT"))

    pitch, rpm = INITIAL[ws]
    primary = [("CompServo", 1), ("ServoFile", '"IEA15-land_ServoDyn.dat"')]
    if standalone:
        # stand-alone OpenFAST: its own steady wind and blade-element momentum induction
        primary += [("CompInflow", 1), ("TMax", 700.0)]
        edit(os.path.join(d, "IEA15-land-bem.fst"), primary)
        os.remove(os.path.join(d, "IEA15-land.fst"))
        os.rename(os.path.join(d, "IEA15-land-bem.fst"), os.path.join(d, "IEA15-land.fst"))
        edit(os.path.join(d, "IEA15-land_InflowFile.dat"), [("HWindSpeed", ws)])
    else:
        primary += [("TMax", 10000.0)]   # ERF sets the stop time
        edit(os.path.join(d, "IEA15-land.fst"), primary)
        edit(os.path.join(d, "IEA15-land-bem.fst"), primary)
    edit(os.path.join(d, "IEA15-land_ElastoDyn.dat"),
         [("GenDOF", "True"), ("RotSpeed", f"{rpm:.4f}")]
         + [(f"BlPitch({b})", f"{pitch:.4f}") for b in (1, 2, 3)])
    # no tower drag is put on the flow in these decks, so AeroDyn keeps its tower influence
    edit(os.path.join(d, "IEA15-land_AeroDyn15.dat"), [("TwrPotent", 1), ("TwrShadow", 1)])
    edit(os.path.join(d, "IEA15-land_ServoDyn.dat"), [("DLL_FileName", f'"{libdiscon}"')])


def deck_file(name, d, ws):
    with open(os.path.join(HERE, name + ".i")) as f:
        text = f.read()
    text, n1 = re.subn(r"^(xlo\.velocity\s*=\s*)\S+", lambda m: m.group(1) + str(ws), text, flags=re.M)
    text, n2 = re.subn(r"^(prob\.U_0\s*=\s*)\S+", lambda m: m.group(1) + str(ws), text, flags=re.M)
    if n1 != 1 or n2 != 1:
        sys.exit(f"prepare.py: {name}.i does not have one xlo.velocity and one prob.U_0 line")
    text = text.replace("(9 m/s)", f"({ws:g} m/s)", 1)
    with open(os.path.join(d, name + ".i"), "w") as f:
        f.write(text)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--libdiscon", required=True, help="the ROSCO controller library (libdiscon.so or .dylib)")
    ap.add_argument("--decks", nargs="+", default=DECKS, choices=DECKS)
    ap.add_argument("--speeds", nargs="+", type=float, default=sorted(INITIAL))
    ap.add_argument("--standalone", action="store_true", help="make the stand-alone OpenFAST runs instead")
    ap.add_argument("--out", default=os.path.join(HERE, "runs"))
    a = ap.parse_args()

    lib = os.path.abspath(a.libdiscon)
    if not os.path.isfile(lib):
        sys.exit(f"prepare.py: --libdiscon {lib} is not a file")
    for ws in a.speeds:
        if ws not in INITIAL:
            sys.exit(f"prepare.py: --speeds {ws} is not one of {sorted(INITIAL)}")

    for name in (["standalone"] if a.standalone else a.decks):
        for ws in a.speeds:
            d = os.path.join(a.out, name, f"ws{ws:.1f}")
            if os.path.exists(d):
                sys.exit(f"prepare.py: {d} exists; remove it first")
            os.makedirs(os.path.dirname(d), exist_ok=True)
            model_files(d, ws, lib, a.standalone)
            if not a.standalone:
                deck_file(name, d, ws)
            print(d)


if __name__ == "__main__":
    main()
