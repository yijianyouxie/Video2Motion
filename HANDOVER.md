# Video2Motion 交接文档

**日期：** 2026-10-23  
**范围：** GVHMR / WHAM → BVH → 3ds Max Biped `.bip`  
**当前状态：** 13 / 13 测试通过；15 个 BVH、6 个 BIP 已生成

---

## 1. 项目目标

把输入视频交给 GVHMR 或 WHAM 恢复人体动作，输出可以在 3ds Max Biped 上直接使用的动捕数据。

```
视频
 ├─ GVHMR → hmr4d_results.pt（SMPL-X，22 身体关节）
 └─ WHAM  → wham_output.pkl（SMPL，24 关节）
        ↓  smpl_to_bvh.py
   20 关节 BVH（Biped 命名，Y-up，厘米，30 fps）
        ↓  bvh_to_bip.ms + 3ds Max 2016
   .bip（1.64 m Biped）
```

两个项目的同一视频最终使用同一套朝向约定，方便在 Max 里并排对比。WHAM 默认绕 Y 轴旋转 180°，与 GVHMR 对齐。

---

## 2. 环境与路径

| 角色 | 路径 | 说明 |
|------|------|------|
| Windows 工作区 | `H:\MyProject\Video2Motion` | 脚本、BVH、BIP |
| GVHMR 源码 | `~/GVHMR`（WSL） | 输出在 `outputs/demo/` |
| WHAM 源码 | `~/WHAM`（WSL） | 输出在 `output/demo/` |
| Conda 环境 | `gvhmr` / `wham` | 测试在 `wham` 环境运行 |
| 3ds Max | `C:\Program Files\Autodesk\3ds Max 2016\3dsmax.exe` | headless：`-q -silent -mip -U MAXScript` |
| Body models | `~/GVHMR/inputs/checkpoints/body_models`<br>`~/WHAM/dataset/body_models` | 读取 rest pose |
| 参考工程 | `F:\Comfy-Desktop\ComfyUI-Installs\Comfy-MotionCapture` | 只读参考，原文件未修改 |

WSL 项目路径：

```
/home/liuhaibin/GVHMR
/home/liuhaibin/WHAM
```

Windows 侧通过 `/mnt/h/MyProject/Video2Motion` 访问工作区。

---

## 3. 目录与交付物

```
H:\MyProject\Video2Motion\
├─ HANDOVER.html              # 本交接文档的网页版
├─ HANDOVER.md                # 本文件
├─ bvh_export\
│  ├─ smpl_to_bvh.py          # 转换器（单文件 + 批量）
│  ├─ test_smpl_to_bvh.py     # 13 个测试
│  └─ README.md               # 使用与 Max 导入说明
├─ bip_export\
│  ├─ run_bvh_to_bip.py       # 批量调用 Max 的 runner
│  ├─ bvh_to_bip.ms           # 从参考工程复制的 MAXScript
│  ├─ bvh_to_bip_params.txt   # 当前参数
│  └─ bvh_to_bip_result.txt   # 最近一次 Max 日志
└─ bvh_out\
   ├─ GVHMR\demo\             # 9 BVH + 3 BIP
   ├─ WHAM\demo\              # 6 BVH + 3 BIP（仅 _smplify）
   └─ motoncapture\           # 旧 ComfyUI 流水线产物（6 BVH + 6 BIP）
```

### 当前 BVH

| 来源 | 系列 | 数量 |
|------|------|------|
| GVHMR | 基础 / `_30` / `_30_2long` | 9 |
| WHAM | `_30_smplify` / `_30_2long_smplify` | 6 |

GVHMR 三个基础系列（`last_year_summer`、`man_dance`、`women_dance`）及其 30fps、2long 版本都已导出。WHAM 侧在最近一次清理后只保留 6 个 `_smplify` 目录。

### 当前 BIP

只转换了 `_30` 系列，共 6 个：

```
bvh_out\GVHMR\demo\last_year_summer_30.bip
bvh_out\GVHMR\demo\man_dance_30.bip
bvh_out\GVHMR\demo\women_dance_30.bip
bvh_out\WHAM\demo\last_year_summer_30_smplify\last_year_summer_30.bip
bvh_out\WHAM\demo\man_dance_30_smplify\man_dance_30.bip
bvh_out\WHAM\demo\women_dance_30_smplify\women_dance_30.bip
```

`_30_2long` 与基础系列没有对应 BIP；需要时扩展 runner 的 `TARGETS` 即可。

### WSL 源数据

| 项目 | 路径模式 | 数量 |
|------|----------|------|
| GVHMR | `~/GVHMR/outputs/demo/*/hmr4d_results.pt` | 9 + 1 backup |
| WHAM | `~/WHAM/output/demo/*_smplify/*/wham_output.pkl` | 6 |

`last_year_summer/_vosimple_backup` 是备份结果，批量转换会跳过所有以 `_` 开头的目录。

---

## 4. 流水线

### 4.1 输入参数

| 项目 | 文件 | 使用的 key | 骨架 |
|------|------|------------|------|
| GVHMR | `hmr4d_results.pt` | `smpl_params_global`（`global_orient` / `body_pose` / `betas` / `transl`） | SMPL-X，22 个身体关节 |
| WHAM | `wham_output.pkl` | `pose_world` / `trans_world` / `betas` / `frame_ids` | SMPL，24 关节 |

### 4.2 导出 BVH

转换器：`bvh_export/smpl_to_bvh.py`

1. 读取官方 body model，用该视频的平均 `betas` 跑零姿态，得到 rest 关节位置。
2. 逐级做差得到父关节相对的 `OFFSET`，单位米；再乘 `--scale`（默认 100 = 厘米）。
3. 轴角局部旋转转成 Euler ZXY（`R = Rz · Rx · Ry`），写成 BVH 的 `Zrotation Xrotation Yrotation`。
4. 裁剪成 20 个 Biped 关节，手臂 rest 转 A-pose，世界 yaw 按项目设置。
5. 根节点 `OFFSET` = rest 骨盆位置，位置通道 = SMPL `transl`；世界骨盆 = 两者之和。

WHAM 额外处理：

- 把髋中心的世界平移换算成 SMPL 的 `transl`（`transl = trans_world - R_root · hip_rest`）。
- 按 `frame_ids` 用 slerp / 线性插值补齐缺失帧。

### 4.3 转 BIP

`bip_export/run_bvh_to_bip.py` 复用参考工程的 MAXScript：

1. 把厘米制 BVH 缩放到米制临时副本（参考流水线使用米制）。
2. 写 `bvh_to_bip_params.txt`：输入 BVH、输出 BIP、fps=30、spineLinks=3、elbowOrient=0。
3. 调用 `3dsmax.exe -q -silent -mip -U MAXScript bvh_to_bip.ms`。
4. 检查 `bvh_to_bip_result.txt` 以 `OK` 结束，并确认 BIP 文件非空。

Biped 用固定 1.64 m 高度创建；`.bip` 里的最终骨长由 Biped 决定，不是 BVH 的 `OFFSET`。

---

## 5. 运行命令

### 5.1 导出 BVH

```bash
wsl
source ~/miniconda3/etc/profile.d/conda.sh
conda activate wham
cd /mnt/h/MyProject/Video2Motion/bvh_export

# 单个 GVHMR 结果
python smpl_to_bvh.py ~/GVHMR/outputs/demo/man_dance_30/hmr4d_results.pt

# 单个 WHAM 结果（文件里所有 track 各输出一个 BVH）
python smpl_to_bvh.py ~/WHAM/output/demo/man_dance_30_smplify/man_dance_30/wham_output.pkl

# 批量
python smpl_to_bvh.py --batch
```

参数：

| 参数 | 默认 | 作用 |
|------|------|------|
| `--fps` | 30 | 视频实际帧率 |
| `--scale` | 100 | 米 → 文件单位；厘米 = 100 |
| `--up` | y | Max 中人物躺倒时改用 `z` |
| `--no-arm` | 关 | 关闭 T-pose → A-pose 手臂转换 |
| `--gvhmr-yaw` | 0 | GVHMR 世界 Y 轴旋转 |
| `--wham-yaw` | 180 | WHAM 世界 Y 轴旋转；设 0 恢复 WHAM 原始世界系 |
| `--model-path` | 自动 | 包含 `smpl/` 或 `smplx/` 的目录 |

### 5.2 转 BIP

```bash
cd /mnt/h/MyProject/Video2Motion/bip_export
python3 run_bvh_to_bip.py --list      # 查看 6 个目标
python3 run_bvh_to_bip.py             # 全部重转
python3 run_bvh_to_bip.py --only gvhmr_man_dance_30
```

运行前确认 3ds Max 没有打开。单个文件超时 300 秒，可通过 `--timeout` 调整。

### 5.3 测试

```bash
cd /mnt/h/MyProject/Video2Motion/bvh_export
conda activate wham
python -m unittest -v test_smpl_to_bvh
```

---

## 6. 关键约定

### 6.1 骨架

输入是 SMPL-X 22 关节或 SMPL 24 关节，输出统一为 20 个 Biped 关节：

```
Hips
├─ LeftHip → LeftKnee → LeftAnkle
├─ RightHip → RightKnee → RightAnkle
└─ Chest → Chest2 → Chest3
   ├─ Neck → Head
   ├─ LeftCollar → LeftShoulder → LeftElbow → LeftWrist
   └─ RightCollar → RightShoulder → RightElbow → RightWrist
```

删除了脚（`L_Foot`/`R_Foot`）和手（`L_Hand`/`R_Hand`）。这是参考工程 Biped 流程的规则；代价是脚掌局部旋转丢失，平均 5–8°，最大 36°。

### 6.2 OFFSET（关节间距）

来自官方 SMPL / SMPL-X 模型在 rest pose 下的关节坐标，用该视频的平均 betas，逐级与父关节做差。不是从视频或关键点估计的，也不是每帧变化的。

```text
# last_year_summer_30.bvh，单位 cm
Hips        OFFSET   0.262  -34.487   0.443   # rest 骨盆绝对值
LeftHip     OFFSET   5.278   -9.077  -3.071
LeftKnee    OFFSET   5.167  -40.657  -1.752   # 大腿
LeftAnkle   OFFSET  -4.071  -42.525  -3.234   # 小腿
LeftElbow   OFFSET  -7.461  -26.146  -3.373   # A-pose，主要朝 -Y
```

运动时非根关节只有旋转通道，位置由 `p_j = p_parent + R_parent · OFFSET_j` 得到，所以骨长在整段动画里是刚性的。

### 6.3 坐标与单位

| 项目 | 约定 |
|------|------|
| Up 轴 | 默认 Y-up；`--up z` 输出 Z-up |
| 单位 | 默认厘米（`--scale 100`） |
| 帧率 | 默认 30 fps，写在 BVH 的 `Frame Time` |
| 旋转顺序 | `Zrotation Xrotation Yrotation`，`R = Rz · Rx · Ry` |
| 根平移 | GVHMR 直接用 `transl`；WHAM 用 `trans_world` 换算成 SMPL 的 `transl` |
| 世界朝向 | GVHMR 0°，WHAM +180°，使两个项目同向 |

### 6.4 WHAM 的补帧与时间轴

WHAM 的 `frame_ids` 通常不连续。转换时在缺失帧之间对旋转做 slerp、对位移做线性插值，输出帧数等于 `max(frame_ids) - min(frame_ids) + 1`。BVH 第 0 帧对应第一个被跟踪到的视频帧，不是视频第 0 帧。

---

## 7. 验证状态

**2026-10-23 最新结果：**

```
Ran 13 tests in 3.687s
OK
```

测试覆盖：

- Euler ZXY 往返，包含 ±90° 万向锁
- WHAM 缺失帧的 slerp / 线性补帧
- Euler 到 BVH 的写出与读回正向运动学
- GVHMR / WHAM 生成的 BVH 与官方 `smplx` 关节位置逐帧对比，容差 `1e-4 m`
- Biped 20 关节的 DFS 顺序与父子关系
- 手臂 rest 朝下、`--no-arm` 保留 T-pose
- WHAM 的世界平移换算与 WHAM 自身网格重建对比，容差 `0.1 m`
- 两个项目同一视频的朝向一致性，平均差 < 30°

最后一次实测两个项目的朝向差为 **17.2°**（修复前 163.1°），剩余差异来自两个方法独立的姿态估计。

当前 15 个 BVH 都能解析、关节数为 20、数值有限；6 个 BIP 都存在且非空。

---

## 8. 已知问题与风险

### 高：Euler 通道 ±360° 跳变

每个文件 14–34 处，集中在 Hips 和左右肘。关键帧旋转正确，但线性插值 Euler 的播放器会出现单帧 360° 翻转，Hips 翻转就是整个人转一圈。

**修复：** 在 `build_bvh` 里对 `euler` 沿时间轴做 `np.unwrap`，旋转矩阵不变（实测最大差 5.9e-15）。尚未实施。

涉及文件与数量：

| 文件 | 跳变数 |
|------|--------|
| GVHMR `last_year_summer_30` | 14 |
| GVHMR `man_dance_30` | 31 |
| GVHMR `women_dance_30` | 33 |
| WHAM `last_year_summer_30_smplify` | 14 |
| WHAM `man_dance_30_smplify` | 34 |
| WHAM `women_dance_30_smplify` | 24 |

### 中：脚/手关节被裁剪

脚掌局部旋转丢失，平均 5–8°，最大 36°，脚踝以下会偏僵。直接看 BVH 时更明显；Biped 流程推荐保持 20 关节。

### 中：global 与 incam 轨迹不同

视频里贴合的通常是 `1_incam.mp4`，BVH 用的是 `smpl_params_global`。局部姿态完全一致，但全局根速度与相机旋转后的 incam 速度相关系数只有 0.30–0.46，走位和视角看起来会不一样。相机本身稳定（相对首帧偏差均值 3–4°，最大 6–14°）。

### 中：women_dance 的 GVHMR 假相机

该系列的世界朝向对不齐，属于参考脚本注释里提到的“固定源估计出剧烈旋转的假相机”。`clean_bvh_autodesk.py` 有基于 npz 的修正路径，尚未接入本流水线。

### 中：Biped 重定向损失

`.bip` 使用固定 1.64 m Biped、`spineLinks=3`、肘朝向 angle。最终骨长和关节映射都由 Biped 决定，和 BVH 的源骨架不同。这是参考流程本身的近似。

### 运行：测试依赖 WHAM `_smplify` 源数据

跨项目朝向测试读取 `~/WHAM/output/demo/last_year_summer_30_smplify`。如果该目录被清理，测试会报错，需要同步修改测试 fixture。

### 运行：BIP 转换的前置条件

3ds Max 必须先关闭；单个文件超时 300 秒；转换会生成米制临时副本，成功后已清理。BIP 只覆盖 6 个 `_30` 文件，2long 未转换。

---

## 9. 下一步

- [ ] **加 Euler unwrap 并重转。** 在 `build_bvh` 的 `euler = np.degrees(matrix_to_zxy(R))` 之后做时间轴 unwrap，然后重新生成 15 个 BVH 和 6 个 BIP。
- [ ] **决定脚关节策略。** 直接看 BVH 可以加 `--keep-feet`；Biped 流程建议保持 20 关节。
- [ ] **明确“贴近视频”的优先级。** 如果以视频对齐为准，输出 incam 姿态 + 固定相机/冻结根轨迹，或接入参考工程的 npz 相机修正。
- [ ] **需要时扩展到 2long。** 在 `run_bvh_to_bip.py` 的 `TARGETS` 增加 6 个 2long 条目即可。
- [ ] **把文件数量检查纳入测试。** 断言 15 个 BVH、6 个 BIP、20 关节，避免清理源数据后静默失配。

---

## 10. 变更记录

| 日期 | 变更 |
|------|------|
| 2026-10-20 | 删除两个项目中所有 tennis 相关输出与源视频（16 个文件、4 个目录） |
| 2026-10-20 | 清理 `bvh_out/WHAM/demo`，只保留与 WSL `~/WHAM/output/demo` 对应的 6 个 `_smplify` 目录，删除 12 个 BVH |
| 2026-10-20 | 生成 6 个 `_30` 系列 BIP |
| 2026-10-23 | 新增交接文档；跨项目朝向测试 fixture 改为 `last_year_summer_30_smplify` |

---

## 11. 参考文件

| 文件 | 用途 |
|------|------|
| `F:\...\Comfy-MotionCapture\bvh_to_bip.ms` | Biped 转换的核心逻辑；已复制到 `bip_export\bvh_to_bip.ms`，原文件未修改 |
| `F:\...\Comfy-MotionCapture\clean_bvh_autodesk.py` | Biped 命名、裁剪脚/手、手臂 A-pose 的参考实现 |
| `F:\...\Comfy-MotionCapture\启动服务.bat` | Web 服务启动脚本；转换实际由 `app.py` 调用 Max |
| `F:\...\Comfy-MotionCapture\app.py` | 确认 Max 调用参数与 params 文件格式 |

接手后先跑一遍测试和 `run_bvh_to_bip.py --list`，确认 WSL 源数据仍在，再开始改代码。
