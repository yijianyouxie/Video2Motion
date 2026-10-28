#!/usr/bin/env python3
"""Convert GVHMR (SMPL-X) and WHAM (SMPL) results to Biped-named BVH.

Input skeletons: GVHMR 22 joints, WHAM 24 joints. Output: the 22-joint
Autodesk Character Studio hierarchy (Hips/Chest/.../LeftWrist/LeftToe), with
the hand joints removed and the arm rest pose converted to an A-pose.

The two pipelines' world frames are 180 degrees apart, so WHAM is rotated
by +180 about Y by default to share GVHMR's world frame.

The output targets 3ds Max: Y-up by default (BVH convention), centimetres,
30 fps, world-space root motion preserved.

Examples
--------
    # one GVHMR result
    python smpl_to_bvh.py ~/GVHMR/outputs/demo/last_year_summer_30/hmr4d_results.pt

    # one WHAM result (all tracks)
    python smpl_to_bvh.py ~/WHAM/output/demo/women_dance_30_single/women_dance_30/wham_output.pkl

    # everything already produced by both projects
    python smpl_to_bvh.py --batch

If the character lies on its back in 3ds Max, regenerate with ``--up z``.
"""

import argparse
import sys
from pathlib import Path

import numpy as np

# --------------------------------------------------------------------------- #
# Skeleton definitions (SMPL kinematic tree; SMPL-X body is the same first 22)
# --------------------------------------------------------------------------- #
SMPL_NAMES = [
    "Pelvis",
    "L_Hip", "R_Hip", "Spine1", "L_Knee", "R_Knee", "Spine2",
    "L_Ankle", "R_Ankle", "Spine3", "L_Foot", "R_Foot",
    "Neck", "L_Collar", "R_Collar", "Head",
    "L_Shoulder", "R_Shoulder", "L_Elbow", "R_Elbow",
    "L_Wrist", "R_Wrist", "L_Hand", "R_Hand",
]
SMPL_PARENTS = [-1, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 9, 12, 13, 14, 16, 17, 18, 19, 20, 21]

DEFAULT_GVHMR_MODELS = Path.home() / "GVHMR/inputs/checkpoints/body_models"
DEFAULT_WHAM_MODELS = Path.home() / "WHAM/dataset/body_models"
DEFAULT_OUT_DIR = Path(__file__).resolve().parent.parent / "bvh_out"

# GVHMR and WHAM define their world frames 180 degrees apart (the camera-space
# body orientations agree, but one pipeline's world +Z points the other way).
# Rotating WHAM by 180 about Y puts both pipelines in the same world frame.
GVHMR_DEFAULT_YAW = 0.0
WHAM_DEFAULT_YAW = 180.0

# Euler channel convention used for every joint: R = Rz @ Rx @ Ry.
CHANNEL_ORDER = ("Zrotation", "Xrotation", "Yrotation")

# Autodesk Character Studio (Biped) naming.
BIPED_RENAME = {
    "Pelvis": "Hips",
    "L_Hip": "LeftHip", "R_Hip": "RightHip",
    "L_Knee": "LeftKnee", "R_Knee": "RightKnee",
    "L_Ankle": "LeftAnkle", "R_Ankle": "RightAnkle",
    "Spine1": "Chest", "Spine2": "Chest2", "Spine3": "Chest3",
    "Neck": "Neck", "Head": "Head",
    "L_Collar": "LeftCollar", "R_Collar": "RightCollar",
    "L_Shoulder": "LeftShoulder", "R_Shoulder": "RightShoulder",
    "L_Elbow": "LeftElbow", "R_Elbow": "RightElbow",
    "L_Wrist": "LeftWrist", "R_Wrist": "RightWrist",
    "L_Foot": "LeftToe", "R_Foot": "RightToe",
    "L_Hand": "LeftWrist", "R_Hand": "RightWrist",
}
REMOVE_SMPL = {"L_Hand", "R_Hand"}
ARM_OFFSET_JOINTS = {"L_Elbow", "R_Elbow", "L_Wrist", "R_Wrist"}
ARM_ROT_JOINTS = {"L_Shoulder", "R_Shoulder", "L_Elbow", "R_Elbow", "L_Wrist", "R_Wrist"}


# --------------------------------------------------------------------------- #
# Rotations
# --------------------------------------------------------------------------- #
def axis_angle_to_matrix(aa):
    """Rodrigues formula; ``aa`` has shape (..., 3), returns (..., 3, 3)."""
    aa = np.asarray(aa, dtype=np.float64)
    theta = np.linalg.norm(aa, axis=-1, keepdims=True)
    k = np.divide(aa, theta, out=np.zeros_like(aa), where=theta > 1e-12)
    K = np.zeros(aa.shape[:-1] + (3, 3), dtype=np.float64)
    K[..., 0, 1], K[..., 0, 2] = -k[..., 2], k[..., 1]
    K[..., 1, 0], K[..., 1, 2] = k[..., 2], -k[..., 0]
    K[..., 2, 0], K[..., 2, 1] = -k[..., 1], k[..., 0]
    eye = np.broadcast_to(np.eye(3), K.shape).copy()
    return eye + np.sin(theta)[..., None] * K + (1.0 - np.cos(theta))[..., None] * (K @ K)


def zxy_to_matrix(angles):
    """Compose ``Rz(z) @ Rx(x) @ Ry(y)``; ``angles`` is (..., 3)."""
    angles = np.asarray(angles, dtype=np.float64)
    z, x, y = angles[..., 0], angles[..., 1], angles[..., 2]
    cz, sz = np.cos(z), np.sin(z)
    cx, sx = np.cos(x), np.sin(x)
    cy, sy = np.cos(y), np.sin(y)
    Rz = np.zeros(angles.shape[:-1] + (3, 3))
    Rx = np.zeros_like(Rz)
    Ry = np.zeros_like(Rz)
    Rz[..., 0, 0], Rz[..., 0, 1], Rz[..., 1, 0], Rz[..., 1, 1], Rz[..., 2, 2] = cz, -sz, sz, cz, 1.0
    Rx[..., 0, 0], Rx[..., 1, 1], Rx[..., 1, 2], Rx[..., 2, 1], Rx[..., 2, 2] = 1.0, cx, -sx, sx, cx
    Ry[..., 0, 0], Ry[..., 0, 2], Ry[..., 1, 1], Ry[..., 2, 0], Ry[..., 2, 2] = cy, sy, 1.0, -sy, cy
    return Rz @ Rx @ Ry


def matrix_to_zxy(R):
    """Inverse of :func:`zxy_to_matrix`; returns angles (..., 3) of [z, x, y]."""
    R = np.asarray(R, dtype=np.float64)
    x = np.arcsin(np.clip(R[..., 2, 1], -1.0, 1.0))
    z = np.arctan2(-R[..., 0, 1], R[..., 1, 1])
    y = np.arctan2(-R[..., 2, 0], R[..., 2, 2])
    gimbal = np.abs(np.cos(x)) < 1e-6
    z_gimbal = np.arctan2(R[..., 1, 0], R[..., 0, 0])
    z = np.where(gimbal, z_gimbal, z)
    y = np.where(gimbal, 0.0, y)
    return np.stack([z, x, y], axis=-1)


def up_matrix(up):
    """Coordinate change from the BVH Y-up convention to ``up``."""
    if up == "y":
        return np.eye(3)
    if up == "z":  # (x, y, z) -> (x, -z, y)
        return np.array([[1.0, 0.0, 0.0], [0.0, 0.0, -1.0], [0.0, 1.0, 0.0]])
    raise ValueError(f"unknown up axis: {up}")


def _rot_z(degrees):
    c, s = np.cos(np.radians(degrees)), np.sin(np.radians(degrees))
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def _rot_y(degrees):
    c, s = np.cos(np.radians(degrees)), np.sin(np.radians(degrees))
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])


def _rotation_from_to(a, b):
    """Rotation matrix mapping unit vector *a* to unit vector *b*."""
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if c < -1.0 + 1e-8:
        perp = np.array([1., 0., 0.]) if abs(a[0]) < 0.9 else np.array([0., 1., 0.])
        perp -= np.dot(perp, a) * a
        perp /= np.linalg.norm(perp)
        return 2.0 * np.outer(perp, perp) - np.eye(3)
    vx = np.array([[0., -v[2], v[1]], [v[2], 0., -v[0]], [-v[1], v[0], 0.]])
    return np.eye(3) + vx + vx @ vx / (1.0 + c)


# Per-bone constant correction rotations (Biped bone name -> 3x3), applied as a
# world-frame left-multiply on that bone's rotation.  Measured from a Biped
# round-trip; used to pre-distort the BVH so loadMocapFile's own retarget error
# is cancelled.  Empty by default (no behaviour change).
_CALIB = {}


def load_calib(path):
    """Load a calibration .npz written by calib.py."""
    z = np.load(path)
    alias = {"Spine": "Chest", "Spine1": "Chest2", "Spine2": "Chest3",
             "LeftClavicle": "LeftCollar", "LeftUpperArm": "LeftShoulder",
             "LeftForearm": "LeftElbow", "RightClavicle": "RightCollar",
             "RightUpperArm": "RightShoulder", "RightForearm": "RightElbow",
             "LeftThigh": "LeftHip", "LeftCalf": "LeftKnee",
             "RightThigh": "RightHip", "RightCalf": "RightKnee"}
    return {alias.get(k, k): np.asarray(z[k], dtype=np.float64) for k in z.files}


def biped_skeleton(njoints):
    """Keep the Biped joints and return (smpl indices, names, new parents)."""
    keep = [j for j in range(njoints) if SMPL_NAMES[j] not in REMOVE_SMPL]
    index = {old: new for new, old in enumerate(keep)}
    names = [BIPED_RENAME[SMPL_NAMES[j]] for j in keep]
    parents = []
    for j in keep:
        p = SMPL_PARENTS[j]
        while p >= 0 and p not in index:
            p = SMPL_PARENTS[p]
        parents.append(index[p] if p >= 0 else -1)
    return keep, names, parents


# --------------------------------------------------------------------------- #
# Quaternion helpers (for filling WHAM's missing detections)
# --------------------------------------------------------------------------- #
def rotvec_to_quat(aa):
    aa = np.asarray(aa, dtype=np.float64)
    theta = np.linalg.norm(aa, axis=-1, keepdims=True)
    half = 0.5 * theta
    k = np.divide(aa, theta, out=np.zeros_like(aa), where=theta > 1e-12)
    return np.concatenate([np.cos(half), np.sin(half) * k], axis=-1)


def quat_to_rotvec(q):
    q = np.asarray(q, dtype=np.float64)
    q = q / np.linalg.norm(q, axis=-1, keepdims=True)
    q = np.where(q[..., :1] < 0.0, -q, q)
    xyz = q[..., 1:]
    n = np.linalg.norm(xyz, axis=-1, keepdims=True)
    theta = 2.0 * np.arctan2(n, q[..., :1])
    k = np.divide(xyz, n, out=np.zeros_like(xyz), where=n > 1e-12)
    return k * theta


def slerp(q0, q1, t):
    """Shortest-path spherical interpolation. q0/q1: (..., 4), t: scalar."""
    dot = np.sum(q0 * q1, axis=-1)
    q1 = np.where(dot[..., None] < 0.0, -q1, q1)
    dot = np.abs(dot)
    theta = np.arccos(np.clip(dot, -1.0, 1.0))
    parallel = dot > 0.9995
    denom = np.where(parallel, 1.0, np.sin(theta))
    w0 = np.where(parallel, 1.0 - t, np.sin((1.0 - t) * theta) / denom)
    w1 = np.where(parallel, t, np.sin(t * theta) / denom)
    q = w0[..., None] * q0 + w1[..., None] * q1
    return q / np.linalg.norm(q, axis=-1, keepdims=True)


def fill_gaps(pose_aa, trans, frame_ids):
    """Resample onto the contiguous frame range, slerping across missing frames."""
    pose = np.asarray(pose_aa, dtype=np.float64)
    trans = np.asarray(trans, dtype=np.float64)
    ids = np.asarray(frame_ids).astype(np.int64).reshape(-1)
    order = np.argsort(ids)
    ids, pose, trans = ids[order], pose[order], trans[order]

    n, dim = pose.shape
    njoints = dim // 3
    target = np.arange(ids[0], ids[-1] + 1)
    quats = rotvec_to_quat(pose.reshape(n, njoints, 3))
    out_pose = np.zeros((len(target), dim))
    out_trans = np.zeros((len(target), 3))

    for i, fid in enumerate(target):
        k = int(np.searchsorted(ids, fid, side="right")) - 1
        if k >= 0 and ids[k] == fid:
            out_pose[i] = pose[k]
            out_trans[i] = trans[k]
        else:
            k0, k1 = k, k + 1
            a = (fid - ids[k0]) / float(ids[k1] - ids[k0])
            out_pose[i] = quat_to_rotvec(slerp(quats[k0], quats[k1], a)).reshape(-1)
            out_trans[i] = (1.0 - a) * trans[k0] + a * trans[k1]

    return out_pose, out_trans, target


# --------------------------------------------------------------------------- #
# Body models and rest pose
# --------------------------------------------------------------------------- #
def load_model(model_type, model_path):
    """Load SMPL or SMPL-X. ``model_path`` is the folder containing smpl/ smplx/."""
    import smplx

    return smplx.create(
        str(model_path),
        model_type=model_type,
        gender="neutral",
        num_betas=10,
        use_pca=False,
        flat_hand_mean=True,
    )


def rest_joints(model, betas, n_joints):
    """Joint positions of the rest pose (zero pose) for the given shape."""
    import torch

    b = torch.as_tensor(np.asarray(betas, dtype=np.float32)).reshape(1, -1)
    kwargs = {}
    if model.__class__.__name__ == "SMPLX":
        kwargs = dict(
            left_hand_pose=torch.zeros(1, 45),
            right_hand_pose=torch.zeros(1, 45),
            jaw_pose=torch.zeros(1, 3),
            leye_pose=torch.zeros(1, 3),
            reye_pose=torch.zeros(1, 3),
            expression=torch.zeros(1, 10),
        )
    with torch.no_grad():
        out = model(
            betas=b,
            global_orient=torch.zeros(1, 3),
            body_pose=torch.zeros(1, model.NUM_BODY_JOINTS * 3),
            transl=torch.zeros(1, 3),
            **kwargs,
        )
    return out.joints[0, :n_joints].detach().cpu().numpy()


# --------------------------------------------------------------------------- #
# BVH writing
# --------------------------------------------------------------------------- #
def build_bvh(global_orient, body_pose, transl, betas, *, model_type, model_path,
              fps=30.0, scale=100.0, up="y", model=None, arm_convert=True, yaw=0.0):
    """Build Biped-named BVH text.

    Parameters
    ----------
    global_orient : (L, 3) axis-angle
    body_pose : (L, 3 * (J - 1)) axis-angle, local rotations
    transl : (L, 3) SMPL-style translation, i.e. pelvis = J0 + transl
    betas : (L, B) or (B,) shape coefficients (mean is used for bone lengths)
    scale : metres -> file units (100 = centimetres)
    up : "y" for standard BVH, "z" for 3ds Max when the import lies down
    arm_convert : rotate the arm rest pose from T-pose to A-pose (Biped's
        ``loadMocapFile`` expects downward-pointing forearm bones)
    yaw : world rotation about +Y, in degrees (used to align the two pipelines)
    """
    go = np.asarray(global_orient, dtype=np.float64).reshape(-1, 3)
    L = go.shape[0]
    bp = np.asarray(body_pose, dtype=np.float64).reshape(L, -1)
    njoints = 1 + bp.shape[1] // 3
    tr = np.asarray(transl, dtype=np.float64).reshape(L, 3)

    b = np.asarray(betas, dtype=np.float64)
    b = b.reshape(-1, b.shape[-1]).mean(axis=0)

    if model is None:
        model = load_model(model_type, model_path)
    rest = rest_joints(model, b, njoints)

    offsets_all = np.zeros((njoints, 3))
    offsets_all[0] = rest[0]
    for j in range(1, njoints):
        offsets_all[j] = rest[j] - rest[SMPL_PARENTS[j]]

    local = np.concatenate([go, bp], axis=1).reshape(L, njoints, 3)
    R = axis_angle_to_matrix(local)

    # Align the clavicle rest pose with Biped.  Biped expects the
    # clavicle (collar→shoulder bone) to be roughly horizontal, while
    # SMPL's rest clavicle angles upward ~29°.  The spine chain is NOT
    # corrected because loadMocapFile redistributes spine rotation
    # across links, making per-link corrections counterproductive.
    _REST = [
        (13, 16, np.array([1., 0., 0.])),
        (14, 17, np.array([-1., 0., 0.])),
    ]
    _D = {}
    for pj, cj, tgt in _REST:
        o = offsets_all[cj]
        ln = np.linalg.norm(o)
        if ln > 1e-9:
            _D[pj] = _rotation_from_to(tgt, o / ln)
    for j in range(njoints):
        p = SMPL_PARENTS[j]
        Dp = _D.get(p)
        Dj = _D.get(j)
        if j > 0 and Dp is not None:
            offsets_all[j] = Dp.T @ offsets_all[j]
        if Dp is not None or Dj is not None:
            dp = Dp.T if Dp is not None else np.eye(3)
            dj = Dj if Dj is not None else np.eye(3)
            R[:, j] = dp[None] @ R[:, j] @ dj[None]

    if arm_convert:
        M_L, M_R = _rot_z(-90.0), _rot_z(90.0)
        for j in range(njoints):
            name = SMPL_NAMES[j]
            if name not in ARM_ROT_JOINTS and name not in ARM_OFFSET_JOINTS:
                continue
            M = M_L if name.startswith("L_") else M_R
            if name in ARM_OFFSET_JOINTS:
                # Rotate the bone vector by the same M used for the rotation
                # compensation, so world positions stay exact (the reference
                # cleaner's [0, -abs(x), 0] assumes an exactly ±X offset).
                offsets_all[j] = M @ offsets_all[j]
            if name in ("L_Shoulder", "R_Shoulder"):
                R[:, j] = R[:, j] @ M.T
            else:
                R[:, j] = M @ R[:, j] @ M.T

    # Pre-distortion: cancel Biped's per-bone retarget error with a constant
    # world-frame rotation.  Applied to the bone's OWN rotation, because the
    # direction of the bone (bone -> child) is W_bone * offset_child.
    if _CALIB:
        W = np.zeros((L, njoints, 3, 3))
        for j in range(njoints):
            p = SMPL_PARENTS[j]
            W[:, j] = R[:, 0] if p < 0 else W[:, p] @ R[:, j]
            E = _CALIB.get(BIPED_RENAME.get(SMPL_NAMES[j], ""))
            if E is not None:
                W[:, j] = np.einsum("ab,nbc->nac", E.T, W[:, j])
                R[:, j] = W[:, j] if p < 0 else np.einsum("nba,nbc->nac", W[:, p], W[:, j])

    keep, names, parents = biped_skeleton(njoints)
    offsets = offsets_all[keep]
    R = R[:, keep]

    if yaw:
        Ry = _rot_y(yaw)
        R[:, 0] = Ry @ R[:, 0]
        offsets[0] = Ry @ offsets[0]
        tr = (Ry @ tr.T).T

    C = up_matrix(up)
    offsets = (offsets @ C.T) * scale
    tr = (tr @ C.T) * scale

    R = np.einsum("ia,ljab,mb->ljim", C, R, C)
    euler = np.degrees(matrix_to_zxy(R))  # (L, J, 3) as [z, x, y]

    n_out = len(parents)
    children = [[] for _ in range(n_out)]
    for j in range(1, n_out):
        children[parents[j]].append(j)

    lines = ["HIERARCHY"]
    file_order = []

    def write_joint(j, depth):
        file_order.append(j)
        pad = "    " * depth
        lines.append(f"{pad}{'ROOT' if j == 0 else 'JOINT'} {names[j]}")
        lines.append(f"{pad}{{")
        o = offsets[j]
        lines.append(f"{pad}    OFFSET {o[0]:.6f} {o[1]:.6f} {o[2]:.6f}")
        if j == 0:
            lines.append(f"{pad}    CHANNELS 6 Xposition Yposition Zposition "
                         f"Zrotation Xrotation Yrotation")
        else:
            lines.append(f"{pad}    CHANNELS 3 Zrotation Xrotation Yrotation")
        if children[j]:
            for child in children[j]:
                write_joint(child, depth + 1)
        else:
            lines.append(f"{pad}    End Site")
            lines.append(f"{pad}    {{")
            lines.append(f"{pad}        OFFSET 0.000000 0.000000 0.000000")
            lines.append(f"{pad}    }}")
        lines.append(f"{pad}}}")

    write_joint(0, 0)
    lines.append("MOTION")
    lines.append(f"Frames: {L}")
    lines.append(f"Frame Time: {1.0 / fps:.9f}")
    for i in range(L):
        values = [*tr[i], *euler[i, 0]]
        for j in file_order[1:]:
            values.extend(euler[i, j])
        lines.append(" ".join(f"{v:.6f}" for v in values))
    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------- #
# Converters
# --------------------------------------------------------------------------- #
def wham_translation(global_orient, trans_world, hip_rest):
    """Convert WHAM's hip-centred world translation to SMPL's ``transl``.

    WHAM centres the body on the posed hip midpoint before adding
    ``trans_world``; SMPL's translation places the pelvis at ``J0 + transl``.
    """
    R = axis_angle_to_matrix(np.asarray(global_orient, dtype=np.float64).reshape(-1, 3))
    return np.asarray(trans_world, dtype=np.float64).reshape(-1, 3) - np.einsum("lij,j->li", R, hip_rest)


def _mean_betas(betas):
    b = np.asarray(betas, dtype=np.float64)
    return b.reshape(-1, b.shape[-1]).mean(axis=0)


def convert_gvhmr(pt_path, output=None, *, model_path=None, fps=30.0, scale=100.0,
                  up="y", arm_convert=True, yaw=GVHMR_DEFAULT_YAW):
    import torch

    pt_path = Path(pt_path)
    try:
        data = torch.load(str(pt_path), map_location="cpu", weights_only=False)
    except TypeError:
        data = torch.load(str(pt_path), map_location="cpu")
    p = data["smpl_params_global"]

    text = build_bvh(
        np.asarray(p["global_orient"]),
        np.asarray(p["body_pose"]),
        np.asarray(p["transl"]),
        np.asarray(p["betas"]),
        model_type="smplx",
        model_path=model_path or DEFAULT_GVHMR_MODELS,
        fps=fps,
        scale=scale,
        up=up,
        arm_convert=arm_convert,
        yaw=yaw,
    )
    if output is not None:
        out = Path(output)
        if out.suffix.lower() != ".bvh":
            out = out / f"{pt_path.parent.name}.bvh"
    else:
        out = DEFAULT_OUT_DIR / f"{pt_path.parent.name}.bvh"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text)
    return [out]


def convert_wham(pkl_path, output=None, *, model_path=None, fps=30.0, scale=100.0,
                 up="y", arm_convert=True, yaw=WHAM_DEFAULT_YAW):
    import joblib

    pkl_path = Path(pkl_path)
    results = joblib.load(str(pkl_path))
    model_path = model_path or DEFAULT_WHAM_MODELS
    model = load_model("smpl", model_path)

    tracks = list(results.items())
    single = len(tracks) == 1
    if output is None:
        output_dir, exact_file = DEFAULT_OUT_DIR, None
    else:
        output = Path(output)
        if output.suffix.lower() == ".bvh":
            if not single:
                raise ValueError("WHAM file has several tracks; --output must be a directory")
            output_dir, exact_file = output.parent, output
        else:
            output_dir, exact_file = output, None
    base = output_dir / pkl_path.parent.name

    written = []
    for track_id, track in tracks:
        pose = np.asarray(track["pose_world"], dtype=np.float64)
        trans = np.asarray(track["trans_world"], dtype=np.float64)
        betas = _mean_betas(track["betas"])
        frame_ids = np.asarray(track["frame_ids"]).reshape(-1)

        if len(frame_ids) and not np.array_equal(
            frame_ids, np.arange(frame_ids[0], frame_ids[0] + len(frame_ids))
        ):
            pose, trans, _ = fill_gaps(pose, trans, frame_ids)

        hip_rest = rest_joints(model, betas, 24)[[1, 2]].mean(axis=0)
        th = wham_translation(pose[:, :3], trans, hip_rest)

        text = build_bvh(
            pose[:, :3],
            pose[:, 3:],
            th,
            betas,
            model_type="smpl",
            model_path=model_path,
            fps=fps,
            scale=scale,
            up=up,
            arm_convert=arm_convert,
            yaw=yaw,
            model=model,
        )
        if exact_file is not None:
            out = exact_file
        else:
            suffix = "" if single else f"_{track_id}"
            out = base.with_name(base.name + suffix + ".bvh")
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text)
        written.append(out)
    return written


def convert_file(path, output=None, *, dataset=None,
                 gvhmr_yaw=GVHMR_DEFAULT_YAW, wham_yaw=WHAM_DEFAULT_YAW, **kwargs):
    path = Path(path)
    if dataset is None:
        dataset = "gvhmr" if path.suffix.lower() == ".pt" else "wham"
    if dataset == "gvhmr":
        return convert_gvhmr(path, output, yaw=gvhmr_yaw, **kwargs)
    if dataset == "wham":
        return convert_wham(path, output, yaw=wham_yaw, **kwargs)
    raise ValueError(f"unknown dataset: {dataset}")


# --------------------------------------------------------------------------- #
# Batch conversion
# --------------------------------------------------------------------------- #
def convert_all(gvhmr_root, wham_root, out_dir, *, fps=30.0, scale=100.0, up="y",
                model_path=None, arm_convert=True,
                gvhmr_yaw=GVHMR_DEFAULT_YAW, wham_yaw=WHAM_DEFAULT_YAW):
    gvhmr_root = Path(gvhmr_root)
    wham_root = Path(wham_root)
    out_dir = Path(out_dir)
    written = []

    for pt in sorted(gvhmr_root.glob("**/hmr4d_results.pt")):
        rel = pt.parent.relative_to(gvhmr_root)
        if any(part.startswith(("_", ".")) for part in rel.parts):
            continue  # skip backup folders such as _vosimple_backup
        out = out_dir / "GVHMR" / rel.with_suffix(".bvh")
        written += convert_gvhmr(pt, out, model_path=model_path, fps=fps, scale=scale,
                                 up=up, arm_convert=arm_convert, yaw=gvhmr_yaw)

    for pkl in sorted(wham_root.glob("**/wham_output.pkl")):
        rel = pkl.parent.relative_to(wham_root)
        if any(part.startswith(("_", ".")) for part in rel.parts):
            continue
        written += convert_wham(pkl, out_dir / "WHAM" / rel.parent, model_path=model_path,
                                fps=fps, scale=scale, up=up, arm_convert=arm_convert,
                                yaw=wham_yaw)

    return written


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main(argv=None):
    parser = argparse.ArgumentParser(description="Export GVHMR/WHAM results as BVH")
    parser.add_argument("input", nargs="?", help="hmr4d_results.pt or wham_output.pkl")
    parser.add_argument("-o", "--output", help="output .bvh file or directory")
    parser.add_argument("--batch", action="store_true",
                        help="convert every result under the default roots")
    parser.add_argument("--gvhmr-root", default=str(Path.home() / "GVHMR/outputs"))
    parser.add_argument("--wham-root", default=str(Path.home() / "WHAM/output"))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--model-path", default=None,
                        help="folder containing the smpl/ or smplx/ body models")
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--scale", type=float, default=100.0,
                        help="metres to file units (default 100 = centimetres)")
    parser.add_argument("--up", choices=["y", "z"], default="y",
                        help="up axis; use z if the character lies down in 3ds Max")
    parser.add_argument("--no-arm", action="store_true",
                        help="disable the T-pose to A-pose arm rest conversion")
    parser.add_argument("--calib", default=None,
                        help="per-bone correction .npz from calib.py (pre-distortion)")
    parser.add_argument("--gvhmr-yaw", type=float, default=GVHMR_DEFAULT_YAW,
                        help="world Y rotation for GVHMR, degrees (default 0)")
    parser.add_argument("--wham-yaw", type=float, default=WHAM_DEFAULT_YAW,
                        help="world Y rotation for WHAM, degrees (default 180, aligns with GVHMR)")
    args = parser.parse_args(argv)

    if args.calib:
        _CALIB.update(load_calib(args.calib))
        print(f"calib: {len(_CALIB)} bones -> {sorted(_CALIB)}", file=sys.stderr)

    common = dict(fps=args.fps, scale=args.scale, up=args.up,
                  model_path=args.model_path, arm_convert=not args.no_arm)

    if args.batch:
        written = convert_all(args.gvhmr_root, args.wham_root, args.out_dir,
                              gvhmr_yaw=args.gvhmr_yaw, wham_yaw=args.wham_yaw, **common)
    elif args.input:
        written = convert_file(args.input, args.output,
                               gvhmr_yaw=args.gvhmr_yaw, wham_yaw=args.wham_yaw, **common)
    else:
        parser.error("provide an input file or --batch")

    for path in written:
        print(path)
    print(f"wrote {len(written)} BVH file(s)", file=sys.stderr)


if __name__ == "__main__":
    main()
