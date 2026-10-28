#!/usr/bin/env python3
"""BVH -> Biped 骨骼轨迹（CMU 方式），并在送进 Max 前做脚掌 yaw 补偿。

一条命令：
    python run_cmumode.py --bvh <in.bvh> --out <dump.csv> [--fps 30] [--no-ankle-fix]

流程：
  1. bvh_export/ankle_yaw_fix.py  给左右 Ankle 叠加常数 yaw 并转米制 -> _work/<name>_biped.bvh
  2. 写 dump_cmumode_params.txt
  3. 调 3ds Max 跑 dump_bip_cmumode.ms
"""
import argparse
import subprocess
import sys
from pathlib import Path

WORK = Path(__file__).resolve().parent
ROOT = WORK.parent
FIX = ROOT / "bvh_export" / "ankle_yaw_fix.py"
MAX_EXE = "/mnt/c/Program Files/Autodesk/3ds Max 2016/3dsmax.exe"
SCRIPT = WORK / "dump_bip_cmumode.ms"
PARAMS = WORK / "dump_cmumode_params.txt"
RESULT = WORK / "dump_bip_result.txt"


def win(p):
    out = subprocess.check_output(["wslpath", "-w", str(p)], text=True).strip()
    return out.replace("\\", "/")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bvh", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--no-ankle-fix", action="store_true")
    ap.add_argument("--timeout", type=int, default=600)
    args = ap.parse_args()

    src = Path(args.bvh).resolve()
    dst = Path(args.out).resolve()
    if not src.exists():
        sys.exit("missing input: %s" % src)

    staged = WORK / "_work" / (src.stem + "_biped.bvh")
    cmd = [sys.executable, str(FIX), str(src), str(staged), "--to-meters"]
    if args.no_ankle_fix:
        cmd += ["--left", "0", "--right", "0"]
    print("=== ankle_yaw_fix ===", flush=True)
    subprocess.run(cmd, check=True)

    PARAMS.write_text("\n".join([win(staged), win(dst), str(args.fps)]) + "\n")
    if RESULT.exists():
        RESULT.unlink()

    print("=== 3ds Max ===", flush=True)
    proc = subprocess.run([MAX_EXE, "-q", "-silent", "-mip", "-U", "MAXScript", win(SCRIPT)],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, errors="replace", timeout=args.timeout)
    log = RESULT.read_text(errors="replace") if RESULT.exists() else "(no log)"
    print(log)
    ok = dst.exists() and dst.stat().st_size > 0
    print("RESULT:", "OK" if ok else "FAILED", "->", dst)
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
