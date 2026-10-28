"""Tests for smpl_to_bvh: Euler conventions, gap filling, and full BVH round-trips.

Run from the bvh_export directory:
    python -m unittest -v test_smpl_to_bvh
"""

import math
import unittest
from pathlib import Path

import numpy as np

import smpl_to_bvh as m

WHAM_ROOT = Path.home() / "WHAM"
GVHMR_ROOT = Path.home() / "GVHMR"
GVHMR_MODELS = GVHMR_ROOT / "inputs/checkpoints/body_models"
WHAM_MODELS = WHAM_ROOT / "dataset/body_models"


# --------------------------------------------------------------------------- #
# Minimal independent BVH reader + forward kinematics, used to check the writer
# --------------------------------------------------------------------------- #
def parse_bvh(text):
    lines = [ln.strip() for ln in text.strip().splitlines() if ln.strip()]
    i = 0
    assert lines[i] == "HIERARCHY", lines[i]
    i += 1

    names, parents, offsets, channels = [], [], [], []
    stack = []
    while not lines[i].startswith("MOTION"):
        tok = lines[i].split()
        if tok[0] in ("ROOT", "JOINT"):
            names.append(tok[1])
            parents.append(stack[-1] if stack else -1)
            i += 1
            assert lines[i] == "{", lines[i]
            i += 1
            assert lines[i].startswith("OFFSET"), lines[i]
            offsets.append([float(v) for v in lines[i].split()[1:]])
            i += 1
            assert lines[i].startswith("CHANNELS"), lines[i]
            channels.append(lines[i].split()[2:])
            i += 1
            stack.append(len(names) - 1)
        elif tok[0] == "End":
            i += 1
            assert lines[i] == "{", lines[i]
            i += 1
            assert lines[i].startswith("OFFSET"), lines[i]
            i += 1
            assert lines[i] == "}", lines[i]
            i += 1
        elif tok[0] == "}":
            stack.pop()
            i += 1
        else:
            raise AssertionError(f"unexpected line: {lines[i]}")

    assert lines[i].startswith("MOTION"), lines[i]
    i += 1
    nframes = int(lines[i].split(":")[1])
    i += 1
    frame_time = float(lines[i].split(":")[1])
    i += 1
    data = np.array([[float(v) for v in ln.split()] for ln in lines[i : i + nframes]])

    return {
        "names": names,
        "parents": parents,
        "offsets": np.array(offsets),
        "channels": channels,
        "nframes": nframes,
        "frame_time": frame_time,
        "data": data,
    }


def _axis_rotation(axis, degrees):
    a = math.radians(degrees)
    c, s = math.cos(a), math.sin(a)
    if axis == "X":
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=float)
    if axis == "Y":
        return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=float)
    if axis == "Z":
        return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=float)
    raise ValueError(axis)


def bvh_forward_kinematics(parsed):
    """Return per-frame world joint positions (L, J, 3) from a parsed BVH."""
    offsets = parsed["offsets"]
    parents = parsed["parents"]
    channels = parsed["channels"]
    data = parsed["data"]
    nframes = parsed["nframes"]
    njoints = len(parents)

    local_r = np.zeros((nframes, njoints, 3, 3))
    local_t = np.zeros((nframes, njoints, 3))
    col = 0
    for j, chs in enumerate(channels):
        n_pos = sum(1 for c in chs if "position" in c)
        n_rot = len(chs) - n_pos
        if n_pos:
            local_t[:, j] = offsets[j] + data[:, col : col + n_pos]
        else:
            local_t[:, j] = offsets[j]
        col += n_pos
        rot = np.tile(np.eye(3), (nframes, 1, 1))
        for k in range(n_rot):
            ch = chs[n_pos + k]
            rot = rot @ np.stack([_axis_rotation(ch[0].upper(), v) for v in data[:, col + k]])
        col += n_rot
        local_r[:, j] = rot

    world_r = np.zeros_like(local_r)
    world_t = np.zeros_like(local_t)
    for j in range(njoints):  # file order is parent-before-child
        p = parents[j]
        if p < 0:
            world_r[:, j] = local_r[:, j]
            world_t[:, j] = local_t[:, j]
        else:
            world_r[:, j] = world_r[:, p] @ local_r[:, j]
            world_t[:, j] = np.einsum("lik,lk->li", world_r[:, p], local_t[:, j]) + world_t[:, p]
    return world_t


def biped_pairs(n_smpl_joints):
    """(Biped name, SMPL joint index) for every joint kept in the output."""
    kept = [j for j in range(n_smpl_joints) if m.SMPL_NAMES[j] not in m.REMOVE_SMPL]
    return [(m.BIPED_RENAME[m.SMPL_NAMES[j]], j) for j in kept]


def assert_fk_matches(test, parsed, ref):
    """Compare BVH FK with smplx joints after the Biped skeleton conversion."""
    fk = bvh_forward_kinematics(parsed)
    by_name = {parsed["names"][i]: fk[:, i] for i in range(len(parsed["names"]))}
    for biped_name, j in biped_pairs(ref.shape[1]):
        err = float(np.abs(by_name[biped_name] - ref[:, j]).max())
        test.assertLess(err, 1e-4, f"{biped_name}: {err}")


# --------------------------------------------------------------------------- #
# Euler conversion
# --------------------------------------------------------------------------- #
class TestEuler(unittest.TestCase):
    def test_identity_maps_to_zero(self):
        np.testing.assert_allclose(m.matrix_to_zxy(np.eye(3)), np.zeros(3), atol=1e-12)

    def test_roundtrip_random_rotations(self):
        rng = np.random.default_rng(0)
        aa = rng.normal(size=(500, 3))
        aa *= rng.uniform(0.0, math.pi, size=(500, 1)) / np.linalg.norm(aa, axis=1, keepdims=True)
        R = m.axis_angle_to_matrix(aa)
        angles = m.matrix_to_zxy(R)
        np.testing.assert_allclose(m.zxy_to_matrix(angles), R, atol=1e-10)

    def test_gimbal_lock(self):
        for x in (math.pi / 2, -math.pi / 2):
            R = m.zxy_to_matrix(np.array([0.7, x, 0.3]))
            angles = m.matrix_to_zxy(R)
            np.testing.assert_allclose(m.zxy_to_matrix(angles), R, atol=1e-10)


class TestUpAxis(unittest.TestCase):
    def test_z_up_maps_y_to_z(self):
        C = m.up_matrix("z")
        np.testing.assert_allclose(C @ np.array([0.0, 1.0, 0.0]), np.array([0.0, 0.0, 1.0]), atol=1e-12)
        np.testing.assert_allclose(m.up_matrix("y"), np.eye(3), atol=1e-12)


# --------------------------------------------------------------------------- #
# Gap filling
# --------------------------------------------------------------------------- #
class TestGapFill(unittest.TestCase):
    def test_preserves_known_frames_and_fills_gaps(self):
        frame_ids = np.array([3, 4, 7, 8])
        pose = np.zeros((4, 6))
        pose[:, 2] = [0.0, 0.1, 1.0, 1.1]
        trans = np.arange(12, dtype=float).reshape(4, 3)

        pose_f, trans_f, ids_f = m.fill_gaps(pose, trans, frame_ids)

        self.assertEqual(len(ids_f), 6)  # frames 3..8
        np.testing.assert_array_equal(ids_f, np.arange(3, 9))
        for src, dst in [(0, 0), (1, 1), (2, 4), (3, 5)]:
            np.testing.assert_allclose(pose_f[dst], pose[src], atol=1e-6)
            np.testing.assert_allclose(trans_f[dst], trans[src], atol=1e-6)
        self.assertTrue(np.all(np.isfinite(pose_f)))
        self.assertTrue(np.all(np.isfinite(trans_f)))

    def test_midpoint_rotation_is_45_degrees(self):
        frame_ids = np.array([0, 2])
        pose = np.zeros((2, 3))
        pose[1, 2] = math.pi / 2
        trans = np.zeros((2, 3))

        pose_f, _, _ = m.fill_gaps(pose, trans, frame_ids)

        R = m.axis_angle_to_matrix(pose_f[1])
        expected = m.axis_angle_to_matrix(np.array([0.0, 0.0, math.pi / 4]))
        np.testing.assert_allclose(R, expected, atol=1e-6)


# --------------------------------------------------------------------------- #
# Full BVH round-trips against the official smplx implementation
# --------------------------------------------------------------------------- #
class TestGvhmrExport(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import torch

        path = sorted(GVHMR_ROOT.glob("outputs/**/hmr4d_results.pt"))[0]
        try:
            data = torch.load(str(path), map_location="cpu", weights_only=False)
        except TypeError:
            data = torch.load(str(path), map_location="cpu")
        p = data["smpl_params_global"]
        cls.n = 5
        cls.global_orient = p["global_orient"][: cls.n].numpy()
        cls.body_pose = p["body_pose"][: cls.n].numpy()
        cls.transl = p["transl"][: cls.n].numpy()
        cls.betas = p["betas"][: cls.n].numpy().mean(axis=0)

    def test_bvh_matches_smplx_forward_kinematics(self):
        import torch

        text = m.build_bvh(
            self.global_orient,
            self.body_pose,
            self.transl,
            self.betas,
            model_type="smplx",
            model_path=GVHMR_MODELS,
            scale=1.0,
        )
        parsed = parse_bvh(text)
        self.assertEqual(len(parsed["names"]), 22)
        self.assertEqual(parsed["nframes"], self.n)
        np.testing.assert_allclose(parsed["frame_time"], 1.0 / 30.0, atol=1e-9)

        model = m.load_model("smplx", GVHMR_MODELS)
        B = self.n
        with torch.no_grad():
            out = model(
                betas=torch.tensor(np.tile(self.betas, (B, 1))).float(),
                global_orient=torch.tensor(self.global_orient).float(),
                body_pose=torch.tensor(self.body_pose).float(),
                transl=torch.tensor(self.transl).float(),
                left_hand_pose=torch.zeros(B, 45),
                right_hand_pose=torch.zeros(B, 45),
                jaw_pose=torch.zeros(B, 3),
                leye_pose=torch.zeros(B, 3),
                reye_pose=torch.zeros(B, 3),
                expression=torch.zeros(B, 10),
            )
        ref = out.joints[:, :22].numpy()
        assert_fk_matches(self, parsed, ref)


class TestWhamExport(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import joblib

        path = sorted(WHAM_ROOT.glob("output/**/wham_output.pkl"))[0]
        results = joblib.load(str(path))
        track = results[next(iter(results))]
        cls.n = 5
        cls.pose_cam = np.asarray(track["pose"][: cls.n], dtype=float)
        cls.pose_world = np.asarray(track["pose_world"][: cls.n], dtype=float)
        cls.trans_world = np.asarray(track["trans_world"][: cls.n], dtype=float)
        betas = np.asarray(track["betas"], dtype=float)
        cls.betas = betas.reshape(-1, 10)[: cls.n].mean(axis=0) if betas.ndim > 1 else betas

    def _hip_rest(self, model):
        return m.rest_joints(model, self.betas, 24)[[1, 2]].mean(axis=0)

    def _build(self, arm_convert=True):
        model = m.load_model("smpl", WHAM_MODELS)
        th = m.wham_translation(self.pose_world[:, :3], self.trans_world, self._hip_rest(model))
        text = m.build_bvh(
            self.pose_world[:, :3],
            self.pose_world[:, 3:],
            th,
            self.betas,
            model_type="smpl",
            model_path=WHAM_MODELS,
            scale=100.0,
            arm_convert=arm_convert,
        )
        return parse_bvh(text)

    def test_biped_hierarchy(self):
        parsed = self._build()
        expected_names = [
            "Hips",
            "LeftHip", "LeftKnee", "LeftAnkle", "LeftToe",
            "RightHip", "RightKnee", "RightAnkle", "RightToe",
            "Chest", "Chest2", "Chest3", "Neck", "Head",
            "LeftCollar", "LeftShoulder", "LeftElbow", "LeftWrist",
            "RightCollar", "RightShoulder", "RightElbow", "RightWrist",
        ]
        expected_parents = [-1, 0, 1, 2, 3, 0, 5, 6, 7, 0, 9, 10,
                            11, 12, 11, 14, 15, 16, 11, 18, 19, 20]
        self.assertEqual(parsed["names"], expected_names)
        self.assertEqual(parsed["parents"], expected_parents)

    def test_arm_rest_points_down(self):
        parsed = self._build()
        offsets = {n: parsed["offsets"][i] for i, n in enumerate(parsed["names"])}
        for name in ("LeftElbow", "RightElbow", "LeftWrist", "RightWrist"):
            o = offsets[name]
            self.assertLess(o[1], 0.0)
            self.assertGreater(abs(o[1]), 3.0 * max(abs(o[0]), abs(o[2])), name)

    def test_no_arm_keeps_t_pose(self):
        parsed = self._build(arm_convert=False)
        offsets = {n: parsed["offsets"][i] for i, n in enumerate(parsed["names"])}
        self.assertGreater(abs(offsets["LeftElbow"][0]), 10.0)

    def test_bvh_matches_smpl_forward_kinematics(self):
        import torch

        model = m.load_model("smpl", WHAM_MODELS)
        th = m.wham_translation(self.pose_world[:, :3], self.trans_world, self._hip_rest(model))

        text = m.build_bvh(
            self.pose_world[:, :3],
            self.pose_world[:, 3:],
            th,
            self.betas,
            model_type="smpl",
            model_path=WHAM_MODELS,
            scale=1.0,
        )
        parsed = parse_bvh(text)
        self.assertEqual(len(parsed["names"]), 22)
        self.assertEqual(parsed["nframes"], self.n)

        B = self.n
        with torch.no_grad():
            out = model(
                betas=torch.tensor(np.tile(self.betas, (B, 1))).float(),
                global_orient=torch.tensor(self.pose_world[:, :3]).float(),
                body_pose=torch.tensor(self.pose_world[:, 3:]).float(),
                transl=torch.tensor(th).float(),
            )
        ref = out.joints[:, :24].numpy()
        assert_fk_matches(self, parsed, ref)

    def test_translation_matches_wham_world_mesh(self):
        """The `th` we feed to SMPL must reproduce WHAM's own world-space mesh."""
        import torch
        from scipy.spatial.transform import Rotation

        model = m.load_model("smpl", WHAM_MODELS)
        th = m.wham_translation(self.pose_world[:, :3], self.trans_world, self._hip_rest(model))
        reg = np.load(WHAM_MODELS / "J_regressor_wham.npy")
        B = self.n

        with torch.no_grad():
            cam = model(
                betas=torch.tensor(np.tile(self.betas, (B, 1))).float(),
                global_orient=torch.tensor(self.pose_cam[:, :3]).float(),
                body_pose=torch.tensor(self.pose_cam[:, 3:]).float(),
                transl=torch.zeros(B, 3),
            )
            world = model(
                betas=torch.tensor(np.tile(self.betas, (B, 1))).float(),
                global_orient=torch.tensor(self.pose_world[:, :3]).float(),
                body_pose=torch.tensor(self.pose_world[:, 3:]).float(),
                transl=torch.tensor(th).float(),
            )
        V_cam = cam.vertices.numpy()
        V_mine = world.vertices.numpy()

        for f in range(B):
            offset = (reg @ V_cam[f])[[11, 12]].mean(axis=0)
            Rc = Rotation.from_rotvec(self.pose_cam[f, :3]).as_matrix()
            Rw = Rotation.from_rotvec(self.pose_world[f, :3]).as_matrix()
            W = Rw @ Rc.T
            V_wham = (V_cam[f] - offset) @ W.T + self.trans_world[f]
            np.testing.assert_allclose(V_mine[f], V_wham, atol=0.1)


# --------------------------------------------------------------------------- #
# Cross-pipeline world alignment
# --------------------------------------------------------------------------- #
class TestWorldAlignment(unittest.TestCase):
    def test_wham_and_gvhmr_face_the_same_way(self):
        import tempfile

        gv_path = GVHMR_ROOT / "outputs/demo/last_year_summer_30/hmr4d_results.pt"
        wh_path = next((WHAM_ROOT / "output/demo/last_year_summer_30_smplify").glob("*/wham_output.pkl"))

        with tempfile.TemporaryDirectory() as tmp:
            gv_out = m.convert_gvhmr(gv_path, Path(tmp) / "gv.bvh", model_path=GVHMR_MODELS)[0]
            wh_out = m.convert_wham(wh_path, Path(tmp) / "wh", model_path=WHAM_MODELS)[0]
            gp = parse_bvh(Path(gv_out).read_text())
            wp = parse_bvh(Path(wh_out).read_text())

        gpos = bvh_forward_kinematics(gp)
        wpos = bvh_forward_kinematics(wp)
        gi = {n: i for i, n in enumerate(gp["names"])}
        wi = {n: i for i, n in enumerate(wp["names"])}

        def yaw(p, idx):
            left = p[:, idx["LeftHip"]] - p[:, idx["RightHip"]]
            fwd = np.cross(left, np.array([0.0, 1.0, 0.0]))
            return np.degrees(np.arctan2(fwd[:, 0], fwd[:, 2]))

        yg, yw = yaw(gpos, gi), yaw(wpos, wi)
        n = min(len(yg), len(yw))
        diff = (yg[:n:5] - yw[:n:5] + 180.0) % 360.0 - 180.0
        self.assertLess(float(np.mean(np.abs(diff))), 30.0,
                        f"mean facing difference {np.mean(np.abs(diff)):.1f} deg")


if __name__ == "__main__":
    unittest.main()
