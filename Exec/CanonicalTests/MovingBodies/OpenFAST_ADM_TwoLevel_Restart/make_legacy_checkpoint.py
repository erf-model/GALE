#!/usr/bin/env python3
"""Turn a checkpoint into a layout an earlier version of the moving bodies wrote.

ERF writes the anchor level's momentum source (N/m^3) of structure model "gale" to
<chk>/StructureCoarseSource/{Level,x_faces,y_faces,z_faces}. Earlier versions wrote it elsewhere:

  bodies_dir  the bodies' own hooks, before they became structure model "gale", wrote the same
              source to <chk>/moving_bodies/StructureCoarseSource;
  force       older versions wrote the anchor level's face forces (N), the source times the face
              volume, to <chk>/moving_bodies/force_{x,y,z}.

This script rewrites a checkpoint written now into one of those layouts, so that the restart
tests can check that such a checkpoint is still read:

    python3 make_legacy_checkpoint.py <chk> bodies_dir
    python3 make_legacy_checkpoint.py <chk> force <face volume in m^3>

The face volume is dx dy dz of the anchor level (a uniform-dz mesh, where the face Jacobian
is 1). <chk>/StructureCoarseSource is removed afterwards.
"""
import array
import os
import re
import shutil
import sys


def scale_fabs(header_path, old_prefix, new_prefix, out_dir, factor):
    """Copy a VisMF MultiFab (header and data files) under a new name, every value times factor."""
    with open(header_path) as f:
        header = f.read()
    entries = re.findall(r"FabOnDisk: (\S+) (\d+)", header)
    if not entries:
        sys.exit(f"{header_path}: no FabOnDisk entries")
    src_dir = os.path.dirname(header_path)
    for name in sorted({e[0] for e in entries}):
        shutil.copyfile(os.path.join(src_dir, name), os.path.join(out_dir, name.replace(old_prefix, new_prefix, 1)))
    for name, offset in entries:
        path = os.path.join(out_dir, name.replace(old_prefix, new_prefix, 1))
        with open(path, "r+b") as f:
            f.seek(int(offset))
            fab_header = f.readline().decode()
            # FAB ((8, (64 11 52 0 1 12 0 1023)),(8, (8 7 6 5 4 3 2 1)))((lo) (hi) (type)) ncomp;
            # the byte order (8 7 6 5 4 3 2 1) is how AMReX labels little-endian doubles
            if "(8, (8 7 6 5 4 3 2 1))" not in fab_header or "(64 11 52 0 1 12 0 1023)" not in fab_header:
                sys.exit(f"{path}: expected little-endian doubles, found {fab_header.strip()}")
            box = re.search(r"\(\((-?\d+),(-?\d+),(-?\d+)\) \((-?\d+),(-?\d+),(-?\d+)\)", fab_header)
            ncomp = int(fab_header.split()[-1])
            lo = [int(box.group(i)) for i in (1, 2, 3)]
            hi = [int(box.group(i)) for i in (4, 5, 6)]
            n = ncomp
            for d in range(3):
                n *= hi[d] - lo[d] + 1
            start = f.tell()
            values = array.array("d")
            values.fromfile(f, n)
            for i in range(n):
                values[i] *= factor
            f.seek(start)
            values.tofile(f)
    with open(os.path.join(out_dir, os.path.basename(header_path).replace(old_prefix, new_prefix, 1)), "w") as f:
        f.write(header.replace(f"FabOnDisk: {old_prefix}", f"FabOnDisk: {new_prefix}"))


def main():
    if len(sys.argv) < 3 or sys.argv[2] not in ("bodies_dir", "force"):
        sys.exit(__doc__)
    if len(sys.argv) != (4 if sys.argv[2] == "force" else 3):
        sys.exit(__doc__)
    chk = sys.argv[1]
    src_dir = os.path.join(chk, "StructureCoarseSource")
    out_dir = os.path.join(chk, "moving_bodies")
    if not os.path.isfile(os.path.join(src_dir, "x_faces_H")):
        sys.exit(f"{src_dir}: no x_faces_H")
    if not os.path.isdir(out_dir):
        sys.exit(f"{out_dir}: no such directory")
    if sys.argv[2] == "bodies_dir":
        shutil.move(src_dir, os.path.join(out_dir, "StructureCoarseSource"))
        print(f"{chk}: StructureCoarseSource moved to moving_bodies/StructureCoarseSource")
        return
    volume = float(sys.argv[3])
    for face, force in (("x_faces", "force_x"), ("y_faces", "force_y"), ("z_faces", "force_z")):
        scale_fabs(os.path.join(src_dir, face + "_H"), face, force, out_dir, volume)
    shutil.rmtree(src_dir)
    print(f"{chk}: StructureCoarseSource rewritten as moving_bodies/force_x, _y, _z (face volume {volume} m^3)")


if __name__ == "__main__":
    main()
