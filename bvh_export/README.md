# SMPL → BVH 导出（GVHMR / WHAM）

把 GVHMR 和 WHAM 输出的 SMPL / SMPL-X 参数转成通用 BVH，目标是 3ds Max。

- 输入：**GVHMR 22 关节**（SMPL-X 身体骨架）、**WHAM 24 关节**（SMPL 骨架）
- 输出：**22 关节的 Autodesk Character Studio 层级**，关节命名与
  `clean_bvh_autodesk.py` 一致：
  `Hips / Chest / Chest2 / Chest3 / Neck / Head / LeftHip / LeftKnee /
  LeftAnkle / LeftToe / LeftCollar / LeftShoulder / LeftElbow / LeftWrist`（右侧同理）
- 保留脚趾（`L_Foot`→`LeftToe`），删除手（`L_Hand`/`R_Hand`）节点。
  `LeftToe` / `RightToe` 是 3ds Max 规范里唯一的脚趾命名，作为 `LeftAnkle` /
  `RightAnkle` 的子节点；去掉它脚掌骨向量不会写进 BVH，Biped 的 `Toe` 也没有数据
- 手臂 rest 从 T-pose（横伸）转成 A-pose（下垂），修复 Biped
  `loadMocapFile` 后手骨垂直前臂的问题；`--no-arm` 可关闭
- 保留世界坐标位移（root motion），不是原地动画
- **两个项目的世界坐标系相差 180°**：相机空间的姿态是一致的，但世界 +Z 的定义相反。
  默认把 WHAM 的输出绕 Y 轴旋转 180°，与 GVHMR 对齐；可用
  `--gvhmr-yaw` / `--wham-yaw` 覆盖（例如 `--wham-yaw 0` 保留 WHAM 原始世界系）
- 输出 Y-up、厘米、30 fps 的标准 BVH

## 文件

| 文件 | 说明 |
|------|------|
| `smpl_to_bvh.py` | 转换器（单文件 + 批量） |
| `test_smpl_to_bvh.py` | 测试：欧拉角往返、补帧、BVH 正向运动学与 smplx 官方实现对比 |

## 运行

两个 conda 环境都能跑（`gvhmr` 或 `wham`），脚本只依赖 `numpy`、`torch`、`smplx`、`joblib`。

```bash
conda activate wham
cd /mnt/h/MyProject/Video2Motion/bvh_export

# 单个 GVHMR 结果
python smpl_to_bvh.py ~/GVHMR/outputs/demo/last_year_summer_30/hmr4d_results.pt

# 单个 WHAM 结果（文件里所有 track 各输出一个 BVH）
python smpl_to_bvh.py ~/WHAM/output/demo/women_dance_30_single/women_dance_30/wham_output.pkl

# 批量转换两个项目已生成的全部结果
python smpl_to_bvh.py --batch
```

批量输出目录默认是 `H:\MyProject\Video2Motion\bvh_out\`：

```
bvh_out/GVHMR/demo/last_year_summer_30.bvh
bvh_out/WHAM/demo/women_dance_30_single/women_dance_30.bvh
```

以 `_` 开头的目录（例如 `_vosimple_backup`）会被跳过。

## 参数

| 参数 | 默认 | 说明 |
|------|------|------|
| `-o, --output` | 自动 | 输出 `.bvh` 文件或目录 |
| `--fps` | `30` | 视频实际帧率 |
| `--scale` | `100` | 米 → 文件单位。100 = 厘米；英寸用 39.37 |
| `--up` | `y` | `y` 为标准 BVH；导入 Max 后人物躺倒时改用 `z` |
| `--no-arm` | 关 | 关闭 T-pose → A-pose 手臂转换 |
| `--gvhmr-yaw` | `0` | GVHMR 输出的世界 Y 轴旋转（度） |
| `--wham-yaw` | `180` | WHAM 输出的世界 Y 轴旋转（度），默认与 GVHMR 对齐 |
| `--model-path` | 自动 | 包含 `smpl/` 或 `smplx/` 的模型目录 |
| `--batch` | 关 | 批量转换 |
| `--gvhmr-root` / `--wham-root` / `--out-dir` | 见脚本 | 批量模式的路径 |

## 导入 3ds Max

**Biped（最常用）**

1. 创建 Biped，选中骨盆（Bip01 Pelvis）。
2. `Motion` 面板 → `Motion Capture` 卷展栏 → `Load Motion Capture File`，文件类型选 BVH。
3. 在 `Motion Capture Conversion Parameters` 里调整 Key Reduction / Footstep Extraction，确定。
4. 先存成 `.BIP`，再加载到已蒙皮的角色上，避免直接导入造成的骨骼比例拉伸。

**CAT**

用 `Clip Manager` 导入 BVH，再用 `Capture Animation` 映射到 CAT 骨架。

导入后如果人物是躺着的，用 `--up z` 重新生成；如果人物特别小或特别大，
优先检查 Max 的场景单位，再调 `--scale`（Biped 的 mocap 导入会按 Biped 身高缩放，
所以单位通常不影响最终大小，只影响初始比例）。

如果手臂交叉、肩膀翻转或膝盖朝向不对，这是 Biped 的重定向设定问题，不是 BVH 数据问题：
在导入对话框的 `Knee/Elbow`、`Foot/Hand Limb Orientation` 里切换 `Point / Angle / Auto`，
不同肢体可能需要不同组合。本文件所有关节统一使用 `Zrotation Xrotation Yrotation`，
Biped 对单个 BVH 只支持一种旋转顺序，所以不会遇到混合顺序的问题。

## 实现说明

- 骨骼长度（OFFSET）来自官方 `SMPL_NEUTRAL` / `SMPLX_NEUTRAL` 模型的 rest pose，
  形状用该视频 `betas` 的平均值，所以比例贴合视频中的人物。
- 输出只保留 Biped 需要的 20 个关节：去掉脚和手之后，脚踝、手腕、Head 成为叶子节点。
- 手臂 A-pose 转换：肘/腕的 OFFSET 绕 Z 轴旋转 ∓90°（横伸 → 下垂），
  肩关节旋转右乘 `M⁻¹`，肘/腕旋转做共轭 `M·R·M⁻¹`。这样骨骼朝向变成下垂，
  同时关节世界位置保持不变（FK 测试误差 < 1e-4 m）。
- SMPL 的轴角是相对父关节的局部旋转，直接写成 BVH 的
  `Zrotation Xrotation Yrotation`（R = Rz·Rx·Ry）。
- 根节点 OFFSET = rest 骨盆位置，位移通道 = `transl`，因此
  ` pelvis_world = OFFSET + transl` 与 SMPL 正向运动学一致。
- WHAM 的世界坐标以“摆姿势后的双髋中点”为原点，脚本会把它换算成标准
  SMPL 的 `transl`（`transl = trans_world − R_root · hip_rest`），
  否则人物会随旋转方向漂移约 9 cm。
- WHAM 的 `frame_ids` 通常不连续，脚本会在缺失帧之间对旋转做 slerp、
  对位移做线性插值，保证播放速度和视频一致。BVH 的第 0 帧对应
  **第一个被跟踪到的视频帧**（不是视频第 0 帧）。
- 世界坐标保留；需要原地动画就在 Max 里把 Pelvis 的位移关键帧清零，
  或者在脚本里把 `transl` 减去首帧平移。

## 测试

```bash
conda activate wham
cd /mnt/h/MyProject/Video2Motion/bvh_export
python -m unittest -v test_smpl_to_bvh
```

测试会读取真实的 GVHMR / WHAM 结果和官方 body model，把生成的 BVH 读回来做
正向运动学，与 `smplx` 官方实现的关节位置逐帧比较（去掉脚/手后的 20 个关节，
容差 1e-4 m），并检查 Biped 层级命名和 A-pose 手臂 OFFSET；另外验证 WHAM 的
世界坐标换算与 WHAM 自身的网格重建一致（容差 0.1 m）。
