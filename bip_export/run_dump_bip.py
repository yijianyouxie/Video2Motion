#!/usr/bin/env python3
"""Load a .bip onto a 1.64 m Biped and dump every bone's world position per frame."""
import subprocess
import sys
from pathlib import Path

WORK = Path(__file__).resolve().parent
MAX_EXE = "/mnt/c/Program Files/Autodesk/3ds Max 2016/3dsmax.exe"
SCRIPT = WORK / "dump_bip.ms"
PARAMS = WORK / "dump_bip_params.txt"
RESULT = WORK / "dump_bip_result.txt"


def win(path):
    out = subprocess.check_output(["wslpath", "-w", str(path)], text=True).strip()
    return out.replace("\\", "/")


def main():
    bip, csv = Path(sys.argv[1]), Path(sys.argv[2])
    PARAMS.write_text(win(bip) + "\n" + win(csv) + "\n")
    if RESULT.exists():
        RESULT.unlink()
    cmd = [MAX_EXE, "-q", "-silent", "-mip", "-U", "MAXScript", win(SCRIPT)]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, errors="replace", timeout=600)
    log = RESULT.read_text(errors="replace") if RESULT.exists() else "(no log)"
    print(log)
    print("max exit =", proc.returncode)
    if csv.exists():
        print("csv lines =", sum(1 for _ in csv.open(errors="replace")))
    else:
        print("CSV MISSING")


if __name__ == "__main__":
    main()
