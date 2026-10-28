#!/usr/bin/env python3
"""给 BVH 的左右踝关节叠加一个常数 yaw，让 3ds Max Biped 还原正确的脚掌朝向。

背景：SMPL-X 的脚掌 rest 是外八（约 15-18 度），Biped 默认脚掌朝正前。
loadMocapFile 只搬踝关节旋转、脚掌零位用自己的，于是整条脚掌固定偏 15-18 度。
脚掌是叶子骨，Biped 对它是近似等变的，所以在 Ankle 的局部旋转上左乘一个
父系表达的 yaw 就能精确抵消（实测 18.3 度 -> 6.2 度，脚尖位置误差 6.7% -> 2.5%）。

用法:
    python ankle_yaw_fix.py in.bvh out.bvh
    python ankle_yaw_fix.py in.bvh out_meters.bvh --to-meters
    python ankle_yaw_fix.py in.bvh out.bvh --left 12 --right -10
"""
import argparse
import numpy as np

DEFAULT_LEFT = 15.57
DEFAULT_RIGHT = -12.78


def parse_bvh(path):
    lines = open(path, errors="replace").read().splitlines()
    names, parents, offs, nch, stack = [], [], [], [], []
    for ln in lines:
        s = ln.strip()
        if s == "MOTION":
            break
        if s.startswith("ROOT") or s.startswith("JOINT"):
            names.append(s.split()[1])
            parents.append(stack[-1] if stack else -1)
            offs.append(None)
            nch.append(3)
        elif s.startswith("OFFSET") and offs[-1] is None:
            offs[-1] = np.array([float(x) for x in s.split()[1:4]])
        elif s.startswith("CHANNELS"):
            nch[-1] = int(s.split()[1])
        elif s == "{":
            stack.append(len(names) - 1)
        elif s == "}" and stack:
            stack.pop()
    offs = np.array([o if o is not None else np.zeros(3) for o in offs])
    mi = lines.index("MOTION")
    n = int(lines[mi + 1].split()[1])
    mot = np.array([[float(x) for x in l.split()] for l in lines[mi + 3:mi + 3 + n]])
    return lines, mi, names, parents, offs, nch, mot, n


def zxy(v):
    z, x, y = np.radians(v[..., 0]), np.radians(v[..., 1]), np.radians(v[..., 2])
    cz, sz = np.cos(z), np.sin(z)
    cx, sx = np.cos(x), np.sin(x)
    cy, sy = np.cos(y), np.sin(y)
    R = np.zeros(v.shape[:-1] + (3, 3))
    R[..., 0, 0] = cz * cy - sz * sx * sy
    R[..., 0, 1] = -sz * cx
    R[..., 0, 2] = cz * sy + sz * sx * cy
    R[..., 1, 0] = sz * cy + cz * sx * sy
    R[..., 1, 1] = cz * cx
    R[..., 1, 2] = sz * sy - cz * sx * cy
    R[..., 2, 0] = -cx * sy
    R[..., 2, 1] = sx
    R[..., 2, 2] = cx * cy
    return R


def to_zxy(M):
    x = np.arcsin(np.clip(M[..., 2, 1], -1, 1))
    y = np.arctan2(-M[..., 2, 0], M[..., 2, 2])
    z = np.arctan2(-M[..., 0, 1], M[..., 1, 1])
    return np.degrees(np.stack([z, x, y], -1))


def rot_axis(axis, deg):
    th = np.radians(deg)
    K = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + np.sin(th) * K + (1 - np.cos(th)) * K @ K


def apply_yaw(mot, nch, names, parents, n, yaw_map, up):
    j_n = len(names)
    aa = np.zeros((n, j_n, 3))
    aa[:, 0] = mot[:, 3:6]
    aa[:, 1:] = mot[:, 6:].reshape(n, j_n - 1, 3)
    Rl = zxy(aa)
    W = np.zeros((n, j_n, 3, 3))
    for j in range(j_n):
        p = parents[j]
        W[:, j] = Rl[:, j] if p < 0 else W[:, p] @ Rl[:, j]

    bi = {nm: i for i, nm in enumerate(names)}
    done = []
    for nm, deg in yaw_map.items():
        if nm not in bi or abs(deg) < 1e-6:
            continue
        j = bi[nm]
        p = parents[j]
        if p < 0:
            continue
        Rext = rot_axis(up, deg)
        Wp = W[:, p]
        M = np.einsum("nba,bc,ncd->nad", Wp, Rext, Wp)
        Rl[:, j] = np.einsum("nab,nbc->nac", M, Rl[:, j])
        for k in range(j, j_n):
            pk = parents[k]
            if pk >= 0:
                W[:, k] = W[:, pk] @ Rl[:, k]
        done.append((nm, deg))

    newmot = mot.copy()
    for j in range(j_n):
        if nch[j] == 6:
            newmot[:, 3:6] = to_zxy(Rl[:, j])
        else:
            c = sum(nch[:j])
            newmot[:, c:c + 3] = to_zxy(Rl[:, j])
    return newmot, done


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--left", type=float, default=DEFAULT_LEFT)
    ap.add_argument("--right", type=float, default=DEFAULT_RIGHT)
    ap.add_argument("--to-meters", action="store_true",
                    help="OFFSET 与根位移 x0.01（给按米工作的 Max 场景用）")
    args = ap.parse_args()

    lines, mi, names, parents, offs, nch, mot, n = parse_bvh(args.src)
    UP = np.array([0.0, 1.0, 0.0])          # BVH 是 Y-up
    newmot, done = apply_yaw(mot, nch, names, parents, n,
                             {"LeftAnkle": args.left, "RightAnkle": args.right}, UP)
    for nm, deg in done:
        print(f"  {nm}: yaw {deg:+.2f} deg")

    out = list(lines[:mi + 3])
    for f in range(n):
        out.append(" ".join("%.6f" % v for v in newmot[f]))

    if args.to_meters:
        res = []
        in_motion = False
        for line in out:
            s = line.strip()
            if s == "MOTION":
                in_motion = True
                res.append(line)
                continue
            if not in_motion:
                if s.startswith("OFFSET"):
                    indent = line[: len(line) - len(line.lstrip())]
                    v = [float(x) * 0.01 for x in s.split()[1:4]]
                    res.append("%sOFFSET %.6f %.6f %.6f" % (indent, v[0], v[1], v[2]))
                else:
                    res.append(line)
                continue
            if not s or s.startswith(("Frames:", "Frame Time:")):
                res.append(line)
                continue
            v = [float(x) for x in s.split()]
            v[0] *= 0.01
            v[1] *= 0.01
            v[2] *= 0.01
            res.append(" ".join("%.6f" % x for x in v))
        out = res

    open(args.dst, "w").write("\n".join(out) + "\n")
    print("wrote", args.dst, "(%d frames)" % n)


if __name__ == "__main__":
    main()
