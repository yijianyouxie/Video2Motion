#!/usr/bin/env python3
"""Convert the six `_30` / `_30_smplify` BVHs to Biped .bip with Max 2016.

Reuses a copy of the Comfy-MotionCapture `bvh_to_bip.ms` (copied next to this
script).  The MAXScript reads `bvh_to_bip_params.txt` from its own folder:
    line 1: input BVH
    line 2: output BIP
    line 3: fps
    line 4: spine links
    line 5: elbow orientation (0 = angle)

Our BVHs are in centimetres, while the reference pipeline expects metres
(its clean BVHs have metre-scale offsets), so each input is rewritten to
`_work/<name>.bvh` scaled by 0.01 before Max sees it.

Run in WSL:
    python3 run_bvh_to_bip.py --only gvhmr_last_year_summer_30
    python3 run_bvh_to_bip.py
"""

import argparse
import subprocess
import sys
from pathlib import Path

WORK = Path(__file__).resolve().parent
ROOT = WORK.parent
BVH_OUT = ROOT / "bvh_out"
MAX_EXE = "/mnt/c/Program Files/Autodesk/3ds Max 2016/3dsmax.exe"
SCRIPT = WORK / "bvh_to_bip.ms"
PARAMS = WORK / "bvh_to_bip_params.txt"
RESULT = WORK / "bvh_to_bip_result.txt"

TARGETS = [
    ("gvhmr_last_year_summer_30",
     BVH_OUT / "GVHMR/demo/last_year_summer_30.bvh",
     BVH_OUT / "GVHMR/demo/last_year_summer_30.bip"),
    ("gvhmr_man_dance_30",
     BVH_OUT / "GVHMR/demo/man_dance_30.bvh",
     BVH_OUT / "GVHMR/demo/man_dance_30.bip"),
    ("gvhmr_women_dance_30",
     BVH_OUT / "GVHMR/demo/women_dance_30.bvh",
     BVH_OUT / "GVHMR/demo/women_dance_30.bip"),
    ("wham_last_year_summer_30_smplify",
     BVH_OUT / "WHAM/demo/last_year_summer_30_smplify/last_year_summer_30.bvh",
     BVH_OUT / "WHAM/demo/last_year_summer_30_smplify/last_year_summer_30.bip"),
    ("wham_man_dance_30_smplify",
     BVH_OUT / "WHAM/demo/man_dance_30_smplify/man_dance_30.bvh",
     BVH_OUT / "WHAM/demo/man_dance_30_smplify/man_dance_30.bip"),
    ("wham_women_dance_30_smplify",
     BVH_OUT / "WHAM/demo/women_dance_30_smplify/women_dance_30.bvh",
     BVH_OUT / "WHAM/demo/women_dance_30_smplify/women_dance_30.bip"),
]


def windows_path(path):
    out = subprocess.check_output(["wslpath", "-w", str(path)], text=True).strip()
    return out.replace("\\", "/")


def scale_to_meters(src, dst, factor=0.01):
    lines = src.read_text().splitlines()
    out = []
    in_motion = False
    for line in lines:
        s = line.strip()
        if s == "MOTION":
            in_motion = True
            out.append(line)
            continue
        if not in_motion:
            if s.startswith("OFFSET"):
                indent = line[: len(line) - len(line.lstrip())]
                v = [float(x) * factor for x in s.split()[1:4]]
                out.append(f"{indent}OFFSET {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}")
            else:
                out.append(line)
            continue
        if not s or s.startswith(("Frames:", "Frame Time:")):
            out.append(line)
            continue
        v = [float(x) for x in s.split()]
        v[0] *= factor
        v[1] *= factor
        v[2] *= factor
        out.append(" ".join(f"{x:.6f}" for x in v))
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text("\n".join(out) + "\n")


def run_one(name, src, dst, timeout):
    if not src.exists():
        return False, f"missing input: {src}"
    if dst.exists():
        dst.unlink()

    scaled = WORK / "_work" / f"{name}.bvh"
    scale_to_meters(src, scaled)

    PARAMS.write_text("\n".join([
        windows_path(scaled),
        windows_path(dst),
        "30",
        "3",
        "0",
    ]) + "\n")
    if RESULT.exists():
        RESULT.unlink()

    cmd = [MAX_EXE, "-q", "-silent", "-mip", "-U", "MAXScript", windows_path(SCRIPT)]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired:
        return False, f"timeout after {timeout}s"

    log = RESULT.read_text(errors="replace") if RESULT.exists() else ""
    ok = "OK" in log.splitlines() and dst.exists() and dst.stat().st_size > 0
    tail = "\n".join(log.splitlines()[-8:])
    return ok, f"{tail}\nmax exit={proc.returncode}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", help="target key (see --list)")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()

    if args.list:
        for name, src, dst in TARGETS:
            print(name, "->", dst)
        return

    selected = [t for t in TARGETS if not args.only or t[0] == args.only]
    if not selected:
        parser.error("unknown --only key")

    failed = []
    for name, src, dst in selected:
        print(f"=== {name} ===", flush=True)
        print(f"  in : {src}", flush=True)
        print(f"  out: {dst}", flush=True)
        ok, log = run_one(name, src, dst, args.timeout)
        print(("  OK" if ok else "  FAILED") + f" ({log.splitlines()[-1] if log else ''})",
              flush=True)
        if not ok:
            print(log, flush=True)
            failed.append(name)

    if failed:
        print("FAILED:", ", ".join(failed), file=sys.stderr)
        sys.exit(1)
    print("all done", flush=True)


if __name__ == "__main__":
    main()
