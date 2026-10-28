# BVH → Biped .bip 交接文档

> 日期：2026-10-27
> 范围：SMPL-X → BVH → 3ds Max Biped .bip → 与原视频的比对
> 状态：BVH 转换已验证无损；Biped 环节的误差已量化定位到根因，修复方案已设计、**尚未跑通验证**

本文承接 `HANDOVER.md`（2026-10-23）与 `GVHMR交接文档_2D微调.md`，只讲 BVH/Biped 这一段。

---

## 1. 一句话结论

> **2026-10-28 修正**：手臂 21.8° 的真因是 `mocap.elbowOrient = 0`，髋部偏差的真因是 `.bip` 丢骨架（`loadBipFile` 换默认 1.64 m），两者都不是「rest 不匹配」本身。详见 §8，本节保留原始判断。

`SMPL-X → BVH` 是**数值无损**的（关节位置误差 3e-4 mm）。所有可见偏差都发生在 `BVH → Biped .bip` 这一步，原因是 Biped 的 `loadMocapFile` 会**用 Biped 自己的中性骨架去套源旋转**，而我们的 BVH 中性姿势（SMPL 的前倾脊柱、斜锁骨、A-pose 手臂）与 Biped 默认姿势不一致。脊柱第一节 12.7° 的偏差中，98% 是常数偏置，反解模型残差仅 1.2°——**旋转传对了，零位没对上**。

---

## 2. 目录与产物

```
H:\MyProject\Video2Motion\
├─ bvh_export\
│  ├─ smpl_to_bvh.py          # 转换器（已支持脚趾：LeftToe/RightToe）
│  ├─ ankle_yaw_fix.py        # 【推荐】脚掌 yaw 补偿 + 可选转米制（§8.5）
│  ├─ test_smpl_to_bvh.py     # 13 个测试，全过
│  └─ README.md
├─ bip_export\
│  ├─ bvh_to_bip.ms           # BVH→BIP，含骨架拟合 + 保存 .fig
│  ├─ run_bvh_to_bip.py       # 批量调用 Max
│  ├─ dump_bip.ms             # 【新】载入 .bip、拟合骨架、逐帧导出骨骼世界坐标
│  ├─ dump_rest.ms            # 【新】导出 Biped 的 rest 姿势（zeroAll）
│  ├─ probe_rig.ms            # 探测：spineLinks / 骨长可否缩放
│  ├─ fit_rig.ms              # 按目标长度拟合骨架（独立试验版）
│  ├─ run_dump_bip.py         # dump_bip.ms 的 WSL 调用器
│  ├─ dump_bip_cmumode.ms     # 【推荐】createNew→loadMocap→逐帧导出，参数驱动（§8.4）
│  └─ run_cmumode.py          # 【推荐】一条命令流水线：脚掌补偿→米制→Max→CSV（§8.6）
└─ bvh_out\
   ├─ GVHMR\demo\man_dance_30.bvh   # 22 关节（含脚趾）
   ├─ GVHMR\demo\man_dance_30.bip
   ├─ GVHMR\demo\man_dance_30.fig   # 拟合后的骨架结构（.bip 不含它）
   ├─ _bip_dump\                    # 分析与对比产物，见 §5
   ├─ _bak_20joint\                 # 20 关节旧版 BVH/BIP
   └─ _bak_20261023\                # 更早的备份
```

---

## 3. 流水线

```
视频 → GVHMR → hmr4d_results.pt
        ↓ smpl_to_bvh.py
   22 关节 BVH（Hips…LeftWrist + LeftToe）
        ↓ bvh_to_bip.ms（loadMocapFile → 拟合骨架 → saveFigFile/saveBipFileSegment）
   .bip（动画）+ .fig（骨架比例）
        ↓ 游戏/引擎重定向
```

**关键认知：`.bip` 只存动画，不存骨架比例。** 骨架必须用 `.fig` 单独保存，谁要在 Max 里复现这套比例，必须先 `loadFigFile` 再 `loadBipFile`。

---

## 4. 已验证的结论（都有数据）

### 4.1 SMPL-X → BVH 无损

用独立实现的 BVH 正向运动学（不复用 `smpl_to_bvh.py` 的代码）与 `smplx` 逐帧比对 20 个保留关节：

| 指标 | 值 |
|---|---|
| 位置误差 max | **0.00003 cm**（0.3 µm，float32 极限）|

厘米换算、Y-up、世界根位移、A-pose 手臂变换全部一致。**不要再去查转换器的数学。**

被裁掉的关节只剩脚趾：

| 关节 | 平均局部旋转 | p95 | max |
|---|---:|---:|---:|
| L_Foot | 9.7° | 19.6° | 26.4° |
| R_Foot | 7.6° | 11.9° | 14.1° |

手部无损失（SMPL-X 的 `body_pose` 只到 R_Wrist，手由 hand_pose 控制且为零）。

### 4.2 脚趾命名与层级（对照 3ds Max BVH 规范）

规范要求：`Hips → LeftHip → LeftKnee → LeftAnkle(别名 LeftFoot) → [可选 LeftToe] → End Site`

- 第三个腿节点必须是 `LeftAnkle`（或 `LeftFoot`）；**`LeftFoot` 是踝的别名，不是脚趾**。
- 脚趾只能叫 `LeftToe` / `RightToe`，必须是 `LeftAnkle` 的子节点。
- 规范原文：`CHANNELS data that corresponds to unrecognized JOINT names will be ignored.` —— 名字错了不报错，静默丢弃。

已改：`REMOVE_SMPL = {"L_Hand","R_Hand"}`，`BIPED_RENAME` 增加 `"L_Foot":"LeftToe"`。新 BVH 的 `LeftToe OFFSET = 4.416 -6.211 11.710`（13.97 cm）。

### 4.3 Biped 骨架可以被脚本改写

| 能力 | 做法 | 结果 |
|---|---|---|
| 改骨长 | Figure Mode 下 `scale <bone> [ratio,1,1]`（**只能沿局部 X 轴**） | 23.71 → 29.64 cm，精确 ×1.25 |
| 改脊柱节数 | loadMocapFile 之后、Figure Mode 下 `bipCtrl.spineLinks = n` | n=2 → 2 根；n=3 → 3 根（与 SMPL 的 Spine1/2/3 对应） |
| 保存结构 | Figure Mode 下 `biped.saveFigFile` | `.fig` 10 KB |
| 读取结构 | 也必须在 Figure Mode 下 `biped.loadFigFile` | 否则报 "Cannot run the operation in this mode" |
| 归零 | `biped.zeroAll <biped>` | 得到 rest 姿势 |

### 4.4 骨架拟合结果（man_dance_30）

按 BVH 的 OFFSET 长度逐骨缩放后：

| 骨段 | SMPL | 拟合后 | 拟合前 |
|---|---:|---:|---:|
| 大腿 | 40.59 | **40.59** | 39.52 |
| 小腿 | 42.51 | **42.51** | 39.52 |
| 脚掌 | 13.97 | 14.50 | 14.81 |
| 上臂 | 27.20 | **27.20** | 23.71 |
| 前臂 | 25.75 | **25.75** | 23.71 |
| 锁骨 | 12.31 | **12.31** | 10.27 |
| 脊柱三节 | 10.80/12.79/5.46 | **10.80/12.79/5.46** | 4 节，各约 10.28 |
| 颈 | 16.62 | **16.62** | 5.93 |
| 髋宽 | 10.94 | 15.81 | 15.81（Biped 固定，改不了）|

骨盆相对的关节位置误差：整体 **9.58 → 7.43 cm**。

### 4.5 Biped 输出的误差分解（498 帧，骨段方向）

| 骨段 | 平均 | 波动 | 常数占比 | 判定 |
|---|---:|---:|---:|---|
| 骨盆→脊柱1 | **12.7°** | ±0.3° | 98% | 纯常数 → rest 错配 |
| 脊柱1→脊柱2 | 24.5° | ±9.8° | 60% | 混合 |
| 脊柱2→脊柱3 | **47.8°** | ±5.1° | 89% | 主要是常数 |
| 脊柱3→颈 | 16.6° | ±6.1° | 63% | 混合 |
| 颈→头 | 10.9° | ±5.5° | 50% | 混合，f32 (1.07s) 尖峰 36° |
| 左/右锁骨 | 16.4 / 12.6° | ±6.9 / 7.1 | 58/43% | 混合 |
| 左/右上臂 | 21.8 / 13.6° | ±7.9 / 6.2 | 64/55% | 混合 |
| 左/右前臂 | 7.7 / 2.4° | ±2.4 / 1.2 | 69/50% | 混合 |
| 大腿 / 小腿 | 2.3 / 4.9° | — | — | 正常 |

投影到原始视频（1290×2796，incam 相机）的 2D 误差：**mean 37.7 px / median 34.6 / p95 73.1 / max 138**。作为参照，SMPL 网格自身的重投影误差是 27.9 px。

### 4.6 根因：Biped 用自己的 rest 套源旋转

用实测数据反解“Biped 骨方向 = W_parent(源) × d”里的 d：

| 脊柱节 | 反解出的 Biped rest d | 拟合残差 |
|---|---|---:|
| 脊柱1 | (0.00, 1.00, 0.04) 竖直 | **mean 1.2° / max 4.7°** |
| 脊柱2 | (0.25, 0.90, 0.37) | mean 14.7° |
| 脊柱3 | (0.04, 0.55, 0.84) | mean 28.7° |

第一节残差只有 1.2°，说明**骨盆旋转传递是无误的**；误差全部来自 rest 朝向差异：Biped 竖直，而 SMPL 的 `Pelvis→Spine1` 前倾 10.3°，实测偏差 12.7°。

同一机制作用于锁骨（SMPL 28° 斜向上，Biped 更平）和肩（现有 A-pose hack 只抬了肘/腕的 OFFSET，**没动锁骨和肩**）。

对照 3ds Max 规范原文：

> A correctly oriented BVH file can be verified by setting all rotational values in the first frame of the MOTION section to zeroes.

我们的 BVH 首帧不满足（骨盆 Y 轴 170°、肩 Z 轴约 180°）。

### 4.7 已排除的方向（勿重复）

| 猜测 | 实测 | 结论 |
|---|---|---|
| spineLinks=3 改坏了脊柱 | 4 节 vs 3 节：11.8/25.5/48.9 vs 12.5/24.7/47.9 | **无关** |
| 转换器算错 | FK 比对 0.00003 cm | 无关 |
| 骨长不一致导致 | 拟合后骨长已与 SMPL 一致，误差仍存在 | 不是主因 |
| 脚趾被裁导致脚掌偏 | 加回 LeftToe 后脚掌方向误差 21.45° 一点没变 | 无关（脚掌方向由踝决定）|

---

## 5. 比对工具与产物

全部在 `bvh_out/_bip_dump/`：

| 文件 | 内容 |
|---|---|
| `bip_vs_smpl_on_video.mp4` | **主对比视频**：原始视频 + 绿(SMPL/BVH) + 洋红(BIPED)，1290×2796，498 帧，47 MB |
| `bip_vs_smpl_fit.mp4` | 无背景的骨架并排 + 左脚 2× 放大窗 |
| `bip_on_incam.mp4` | 早期版本（叠在 incam_alpha_skeleton 上，红压红，不要再用）|
| `from_bip.csv` | 当前 .bip 的逐帧骨骼世界坐标（拟合后）|
| `from_bip_22j_unfit.csv` | 未拟合的 22 关节版本 |
| `from_bip_20j.csv` | 20 关节旧版 |
| `rest.csv` | Biped rest 姿势 |
| `bvh_vs_smpl.py` | BVH ↔ SMPL 无损性验证 |
| `diag_seg.py` | 逐骨段方向误差 + 指定时刻 |
| `diag_const.py` | 误差的常数性判定 |
| `fit_rest.py` | 反解 Biped rest 方向（根因验证）|
| `overlay_clean.py` | 生成 `bip_vs_smpl_on_video.mp4` |
| `verify_overlay.py` | 叠加视频自检（颜色/关节命中/包围盒）|

叠加视频的投影链路：`smpl_params_global →(逐帧 Procrustes)→ smpl_params_incam → K_fullimg`，相机残差 0.0000 m；Biped → 世界用**一个**全局刚体变换（残差 5.5 cm），不用逐帧拟合，否则会掩盖动作差异。

---

## 6. 已知问题

> 2026-10-28 状态：第 1 条已定因为 `elbowOrient`（§8.2），第 3 条已用 CMU 方式直导解决（§8.1/8.4），第 4 条已做 yaw 补偿（§8.5）。以下保留原文以记录当时的判断。

1. ~~**脊柱/锁骨/肩的常数偏差没修**。方案已设计（§7），未跑通验证。~~ → 手臂 21.8° 实为 `mocap.elbowOrient = 0`，去掉后 0.49°（§8.2）；脊柱仍有 10–28° 常数偏置，属 Biped rest 固有。
2. **`.bip` 不含骨架比例**。游戏侧的 .bip 仍是默认 1.64 m 骨架；要带比例必须同时给 `.fig`，或者干脆不落 .bip（§8.4）。
3. ~~**髋宽改不了**：Biped 固定 15.81 cm，SMPL 10.94 cm。~~ → 改不了的是 `loadBipFile` 之后的默认骨架；`loadMocapFile` 直导时髋宽 = 源值 11.3753（§8.1）。
4. ~~**脚掌方向偏 21.45°**（常数），来自 Biped 的脚掌 rest 朝向。~~ → 实测 18.26°/15.57°，已用 Ankle yaw 补偿降到 6.16°/5.91°（§8.5）。
5. **Euler ±180° 回绕仍未处理**（HANDOVER §8 的老问题）：`man_dance_30.bvh` 实测 31 处（Hips 11、左右肩各 10）。Biped 内部用四元数可能看不出来，但任何按 Euler 线性插值的消费者会看到人转一圈。
6. **根位置低约 1 m**：`.bip` 骨盆 z≈-0.12，源数据 z≈0.98。游戏若按 root motion 播放需确认是否下沉。
7. **手臂整体比源高 10.2 cm**（Biped 的 `Spine3 → L Clavicle` 骨长 17 cm，源是 9.32 cm）。方向是准的（0.49°），但整条链刚性上移；CMU 同样（30.8%）。属 Biped 拓扑，改不了，详见 §8.8。
8. **锁骨根结构与 CMU 不同**：我们是双点（两锁骨根相距 8.56 cm、高出胸顶 8.34 cm），CMU 是零长度单点（与 Chest2 重合）。这是 SMPL 解剖 vs Biped 简化的差异，不是错误；但重定向到单点锁骨骨架（UE/Mixamo）时需要额外处理，详见 §8.9。

---

## 7. 方案 A 已实测失败（2026-10-27）

### 7.1 先排除：保世界运动的修正对 Biped 完全无效

在 BVH 里把 `LeftShoulder` 的 OFFSET 从 `10.684 5.950 -1.369` 改成 `12.306 0 0`（并做严格的世界运动补偿），重转 BIP 后逐段误差**一位不差**（左锁骨 16.38°→16.38°）。

原因：这套补偿保持 BVH 的世界正向运动学不变，而 Biped 输出的是世界骨方向 → 输入没变，输出必然不变。**任何“保世界运动”的中性姿势修正在 Biped 上都不会有效果。**

### 7.2 预畸变（故意改世界运动）也失败

实现：`calib.py` 用 Kabsch 求出每根骨的常数旋转 `E`（Biped 输出方向 → 源方向），`smpl_to_bvh.py --calib` 把它左乘到该骨的世界旋转上。预测残差本应降到

| 骨段 | 原始 | 常数拟合的预期残差 |
|---|---:|---:|
| 脊柱1→2 | 24.5° | 14.1° |
| 脊柱2→3 | 47.8° | 20.1° |
| 左锁骨 | 16.4° | 9.3° |
| 左上臂 | 21.8° | 16.6° |

实测（两种符号都试了）：

| 骨段 | 基线 | 用 E | 用 Eᵀ |
|---|---:|---:|---:|
| 脊柱1→2 | 24.5° | 26.7° | 21.4° |
| 脊柱2→3 | 47.8° | 41.3° | 53.2° |
| 颈→头 | 10.9° | 26.7° | 36.1° |
| 左锁骨 | 16.4° | 18.0° | 31.0° |
| 左上臂 | 21.8° | **50.4°** | **48.0°** |

**两个方向都变差**，说明“输入转 δ，输出也转 δ”这个假设不成立。用 `dump_rot.ms` 导出的世界旋转直接证实：即使腿部几何误差只有 2.3°，Biped 与源的世界旋转相对差也漂移 36–103°。Biped 的肢体求解器**每帧重新拟合肢体平面/扭转**，输入→输出不是旋转等变的映射。

**结论：常数预畸变在原理上就不成立**，它只会注入新误差。基线已恢复并复验（12.73 / 24.50 / 47.77 / 16.61 / 10.94 / 16.38 / 21.77 / 7.72 / 12.56）。

`--calib` 参数保留在代码里但默认关闭，**不要使用**。

### 7.3 下一步只能走方案 B

> **2026-10-28 更新：本节结论已被 §8 取代。** 骨架直导 + 脚掌 yaw 补偿已把腿部残差做到 3.19%、脚掌方向 15.6–18.3° 降到 5.9–6.2°，不需要逐帧闭环，也不需要放弃 `.bip` 之外的方案。

`.bip` 这条链路要修到可用，只能在每次转换后做**逐帧闭环优化**（改 BVH → 跑 Max → 比对 → 再改），一轮 pipeline 约 5 分钟，498 帧不可能迭代。

所以推荐：**绕过 Biped，直接用 SMPL 的世界旋转驱动游戏骨架**（UE/Unity 的 retarget 或 Blender 约束），或者导出 FBX 骨架动画而不是 .bip。Biped 只适合做“能看个大概”的预览。

**验证指标**（改完必须重跑）：§4.5 的逐段方向误差表、§4.4 的骨长、以及 `bip_vs_smpl_on_video.mp4` 的 2D 误差。

---

## 8. 2026-10-28：三处定因与修复

> 本节修正 §4.6 / §7 的部分归因。结论以本节为准。

### 8.1 髋部不贴合的根因是 `.bip` 不存骨架，不是 Biped 求解器

| | 大腿 | 小腿 | 髋宽 | 髋宽/大腿 |
|---|---:|---:|---:|---:|
| `createNew 1.64` 默认骨架 | 0.395181 | 0.395181 | 0.158072 | 0.400 |
| 源（SMPL-X） | 0.405915 | 0.425126 | 0.113752 | 0.280 |

髋宽比源大 **39%**，大腿只差 2.6%。这一对不平衡把两条腿的根部各往外撑 2.2 cm，再沿骨链传到膝、踝。

排除实验（都已做过，别再重试）：

| 变量 | 做法 | 结果 |
|---|---|---|
| 输入单位 / 根 OFFSET | 米制×厘米 × 根OFFSET(0/337) 四个变体 | 髋宽/大腿 **全是 0.280236**，与源一致 |
| `spineLinks = 3` | 同一 Biped 改前/改后 | thigh、calf、hipw **完全不变** |
| `.fig` | Figure Mode 下 `loadFigFile` | 髋宽 0.158072 → **0.113752** |
| fig + bip | 先 loadFig 再 loadBip | thigh 0.405915 / hipw 0.113752，range 0..497 |

**`loadMocapFile` 本身完全采用源骨架；是 `loadBipFile` 把骨架换成了默认 1.64 m。**
老脚本的两段式（存 `.bip` 再读回）在这一步丢掉了比例，而后面的"骨架拟合"只能沿局部 X 轴改骨长，**改不了髋宽（Y 轴）**。

量化：腿部平均残差 **5.56% → 3.19%**（CMU 2.96%）。

### 8.2 手臂 21.8° 的真凶是 `mocap.elbowOrient = 0`

| 方案 | elbowOrient | spineLinks | 经过 .bip | 左上臂 |
|---|---|---:|---|---:|
| 直导（新脚本） | 默认 point | 4 | ✗ | **0.49°** |
| 干净往返 | 默认 point | 4 | ✓ | **1.39°** |
| sp3 往返 | 默认 point | 3 | ✓ | **1.66°** |
| 老 / comfy 脚本 | **0 = angle** | 3 | ✓ | **21.50°** |

拆解：`.bip` 往返损失 0.9°，`spineLinks=3` 损失 0.27°，**`elbowOrient=0` 贡献 19.8°**。

§4.6 / §7 里"输入→输出非旋转等变、世界旋转漂移 36–103°"的**观测是真的**，但那是在"骨架已经错了 + elbowOrient=0"的前提下测的。骨架正确、用默认 point 时，Biped 对四肢骨**近似等变**（见 8.5 的直接证据）。

**修复：不要设 `mocap.elbowOrient`（保持默认 1 = point）。**

### 8.3 脚掌固定偏 15.6–18.3°：SMPL 的外八 rest

| 侧 | 平均 | 标准差 | 常数性 |
|---|---:|---:|---:|
| 左脚掌 | **18.26°** | 0.15° | 99% |
| 右脚掌 | **15.57°** | 0.16° | 99% |

- 误差主要**绕竖直轴**，双脚都比源"内收"（源是外八）；
- 连带 Toe 位置偏 6.70% / 5.92%（≈ 13.97 cm × sin18°）；
- 整片 8 个时段误差都在 18.2 / 15.6，**动作内部完全正确，只是整只脚被固定拧了一个角**；
- CMU 同类误差只有 3.55°，因为它的 BVH 本来就是为 Biped 构造的。

根因：SMPL 的 `LeftAnkle → LeftToe` offset 带 ~18° 外八，Biped 默认脚掌朝正前，`loadMocapFile` 只搬踝旋转、零位用它自己的。

### 8.4 新方案：CMU 方式直导，不落 `.bip`

`bip_export/dump_bip_cmumode.ms`：`createNew 1.64` → `loadMocapFile` → 逐帧导出。不设 spineLinks、不拟合、不存/读 `.fig`。

结果：`thigh=40.5914`、`hipw=11.3753`（与源一致），腿部残差 3.19%。

### 8.5 脚掌 yaw 补偿（已固化）

脚掌是叶子骨，Biped 对它**近似等变**：输入转多少、输出就转多少。第一次按"反向抵消"加了 −15.57°，误差从 18.26° 涨到 **31.13°**（≈ 18.26 + 12.87），正好证明这一点。

正确做法是在 Ankle 的局部旋转上左乘一个"父系表达"的 yaw：

    R_local' = (W_parentᵀ · R_yaw · W_parent) · R_local
    左 +15.57°   右 −12.78°   （绕 BVH 的 Y 轴）

| | 补偿前 | 补偿后 |
|---|---:|---:|
| 左脚掌方向 | 18.28° | **6.16°** |
| 右脚掌方向 | 15.57° | **5.91°** |
| 左 Toe 位置 | 6.70% | **2.47%** |
| 右 Toe 位置 | 5.92% | **2.29%** |

只动脚掌：Head、Knee、Hip、Hips、Shoulder、Elbow、Wrist、Collar、Chest3 的位置差全部 0.000000。改善覆盖左 99% / 右 95% 的帧，仅 1% 略微变差。

残余：median 5.4°，p95 11.3°，峰值 25.5° @f311–315（那几帧脚掌接近侧翻，固定竖直轴的补偿失效）。

### 8.6 一条命令流水线

    python3 bip_export/run_cmumode.py \
        --bvh bvh_out/GVHMR/demo/man_dance_30.bvh \
        --out bvh_out/_bip_dump/from_bip.csv \
        --fps 30

内部依次：`ankle_yaw_fix.py`（补偿 + 转米制）→ 写 `dump_cmumode_params.txt` → 调 Max 跑 `dump_bip_cmumode.ms`。

| 开关 | 作用 |
|---|---|
| `--no-ankle-fix` | 关闭脚掌补偿 |
| `--fps` | 帧率，默认 30 |

单独调用补偿工具：

    python bvh_export/ankle_yaw_fix.py in.bvh out.bvh              # 保持原单位
    python bvh_export/ankle_yaw_fix.py in.bvh out.bvh --to-meters  # 同时 ÷100
    python bvh_export/ankle_yaw_fix.py in.bvh out.bvh --left 12 --right -10

验证：工具生成的 BVH 与手工验证版**字节一致**；流水线输出 CSV 与已验证的 `from_bip_anklefix.csv` **字节一致**。

### 8.7 换体型时怎么重新标定脚掌补偿

默认角 15.57 / −12.78 是在 `man_dance_30` 这组 betas 上测的，脚掌外八角随体型变化。换人后：

1. 关掉补偿跑一遍：`python3 bip_export/run_cmumode.py --bvh X.bvh --out tmp.csv --no-ankle-fix`
2. 量脚掌方向误差（参考 `bvh_out/_bip_dump/toe_diag.py`，看 `Foot→Toe0` vs `Ankle→Toe` 的均值）；
3. 把左右误差的**相反数**填进 `--left/--right`，重跑确认降到个位数。

注意符号：方向试错时误差会**变大**（18° → 31°），这是正常现象，翻转即可。

### 8.8 手臂整体上移 10.2 cm：Biped 锁骨骨长被放大 82%

| Biped | 对应 BVH | 位置残差 | 上分量 |
|---|---|---:|---:|
| L Clavicle | LeftCollar | **18.38%** | **+17.45%** |
| L UpperArm | LeftShoulder | 18.27% | +17.37% |
| L Forearm | LeftElbow | 18.30% | +17.40% |
| L Hand | LeftWrist | 18.29% | +17.40% |

四个关节的偏移几乎完全相同（差 <0.1%），说明是**整条链刚性平移**，不是关节角度问题——手臂方向误差只有 0.49°（§8.2）。

骨长对照（cm）：

    BVH  ：Chest3 --9.32--> LeftCollar --12.31--> LeftShoulder
    Biped：Spine3 --17.0--> L Clavicle --12.0--> L UpperArm

| 骨段 | Biped | BVH 对应 | 是否吻合 |
|---|---:|---:|---|
| Spine→Spine1 | 10.80 | Chest 10.80 | ✓ |
| Spine1→Spine2 | 12.80 | Chest2 12.79 | ✓ |
| Spine2→Spine3 | 5.1 | Chest3 5.46 | ✓ |
| Spine3→Neck | 16.0 | Neck 16.34 | ✓ |
| **Spine3→Clavicle** | **17.0** | **LeftCollar 9.32** | ✗ 长 82% |

多出的 7.7 cm，加上脊柱逐节累积的 2.9 cm（§8.1 表：Spine3 已偏 +4.78%），正好是实测的 10.2 cm。

脊柱链本身对应正确，只是逐节向上累积：

| Biped | 对应 BVH | 残差 | 上分量 |
|---|---|---:|---:|
| Spine | Hips | 1.56% | +1.37% |
| Spine1 | Chest | 3.88% | +2.70% |
| Spine2 | Chest2 | 4.26% | +2.54% |
| Spine3 | Chest3 | 4.93% | +4.78% |
| Neck | Neck | 7.00% | +4.66% |

CMU 有同样的行为，且更严重：

| | 我们 | CMU |
|---|---:|---:|
| Neck 残差 | 7.00% | 12.39% |
| Clavicle 残差 | 18.38% | 30.78% |
| UpperArm 残差 | 18.27% | 30.81% |

→ **Biped 的通用拓扑行为，与数据源无关。**

**不可修**：`scale` 只能改"本骨到子骨"的骨长轴，改不了子骨挂点偏移。

影响：

- 对比视频里洋红手臂比绿线高 10.2 cm，是固定偏置，不随动作漂移；
- 游戏 retarget 时锁骨偏高、肩线抬高，外观上像"耸肩"，需要在 retarget 阶段对肩部单独做偏移校正。

### 8.9 锁骨根结构差异：SMPL 双点 vs CMU 单点

| | 我们 | CMU |
|---|---:|---:|
| `LeftCollar` 距脊柱顶（Chest3 / Chest2）| **9.32 cm** | **0.00 cm** |
| 两根锁骨根的间距 | **8.56 cm** | **0.00 cm**（重合）|
| 肩点间距（左右）| 29.60 cm（50.6% 躯干）| 5.78 单位（91.0%）|

我们的 `Chest3 → LeftCollar` 向量是 **(右 4.16, 前 −0.15, 上 8.34) cm**；CMU 的 `Chest2 → LeftCollar` 长度为 0，两根锁骨的根都落在脊柱中轴的同一点。

**这是两种「锁骨根」表达方式，不是错误：**

| | 我们的（SMPL 式）| CMU（Biped 式）|
|---|---|---|
| 锁骨根 | 真实节点，位于胸骨上端**两侧** | 零长度虚拟节点，**合并在中轴一点** |
| 手臂链路由 | 胸顶 → 锁骨根（9.3）→ 肩点（12.3）| 胸顶 → 肩点（3.03）|
| 解剖忠实度 | 高 | 低（简化）|
| 与 Biped 骨架契合度 | 低 | 高 |

影响分三层：

| 层面 | 影响 |
|---|---|
| Biped 动作精度 | 锁骨方向误差 0.99°、肩点间距 29.60 → 28.30（−4.4%，1.3 cm），可接受 |
| 手臂高度 | 与本节无关。上移 10.2 cm 是 Biped 把 `Spine3→Clavicle` 放大到 17 cm 造成的（§8.8）|
| 游戏重定向 | 单点锁骨骨架（UE Mannequin / Mixamo）如果按「锁骨根位置」匹配，两个相距 8.6 cm 的点会被拉到同一点，肩线内收 |

**建议**：retarget 时把 `LeftCollar` / `RightCollar` 当作「可压缩节点」——把 8.6 cm 的侧向偏移并入 Clavicle 骨长，或直接丢弃、只用 `LeftShoulder`（肩点）作为锁骨末端。这样既能对上单点骨架，也能绕开 Biped 那 17 cm 的问题。

---

## 9. 复现命令

```bash
# 1) 导出 BVH（22 关节）
wsl.exe -e bash -lc 'source ~/miniconda3/etc/profile.d/conda.sh && conda activate wham \
  && cd /mnt/h/MyProject/Video2Motion/bvh_export \
  && python smpl_to_bvh.py ~/GVHMR/outputs/demo/man_dance_30/hmr4d_results.pt \
     -o /mnt/h/MyProject/Video2Motion/bvh_out/GVHMR/demo/man_dance_30.bvh'

# 2) 测试
wsl.exe -e bash -lc '... conda activate wham && cd .../bvh_export && python -m unittest -v test_smpl_to_bvh'

# 3) BVH → BIP（含骨架拟合 + .fig）  运行前必须关掉 3ds Max
wsl.exe -e bash -lc 'cd /mnt/h/MyProject/Video2Motion/bip_export && python3 run_bvh_to_bip.py --only gvhmr_man_dance_30'

# 4) 导出 .bip 骨骼轨迹（约 75 s）
wsl.exe -e bash -lc '"/mnt/c/Program Files/Autodesk/3ds Max 2016/3dsmax.exe" -q -silent -mip \
  -U MAXScript "H:/MyProject/Video2Motion/bip_export/dump_bip.ms"'

# 5) 分析
wsl.exe -e bash -lc '... conda activate wham && python .../_bip_dump/diag_seg.py'
wsl.exe -e bash -lc '... conda activate wham && python .../_bip_dump/overlay_clean.py'
wsl.exe -e bash -lc '... conda activate wham && python .../_bip_dump/verify_overlay.py'
```

---

## 10. 踩过的坑（省时间用）

1. **MAXScript 的 `sliderTime` / `at time` 单位陷阱**：写 `sliderTime = i * TicksPerFrame` 会被当成**帧数**而不是 tick，时间被夹到末帧，导出的动画看起来“卡住不动”。正确写法：`for t = 0f to 497f do ( at time t (...) )`。
2. **`biped.getHeight` 不存在**，会中断脚本；没有直接取身高的一步 API。
3. **`saveFigFile` / `loadFigFile` 必须在 Figure Mode 下**，否则 "Cannot run the operation in this mode"。
4. **`biped.zeroAll <biped>`** 可用；`bipCtrl.zeroAll()` 不可用。
5. **给 Max 传 Linux 路径会静默不执行**（没有日志、没有输出）。必须 `wslpath -w` 转成 `H:/` 形式。
6. **别用 system python3**（`/usr/bin/python3`）跑分析脚本，没有 numpy；用 `conda activate wham`。
7. **对比视频的红压红**：`incam_alpha_skeleton.mp4` 自带绿色 ViTPose 骨架和半透明红网格，再叠红骨骼等于糊成一片。要用原始视频做背景。
8. **给视频画骨架时曾漏乘相机变换**，洋红骨架被投到画面外、只剩图例里那点像素——这类问题用“统计颜色像素 + 检查关节命中”的自检脚本很快能发现（`verify_overlay.py`）。

---

## 11. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-27 | 保留脚趾：`REMOVE_SMPL` 去掉 L_Foot/R_Foot，重命名为 LeftToe/RightToe，测试与 README 同步 |
| 2026-10-27 | `bvh_to_bip.ms` 增加骨架拟合（按 BVH OFFSET 缩放 18 根骨）与 `saveFigFile` |
| 2026-10-27 | 新增 `dump_bip.ms` / `dump_rest.ms` / `probe_rig.ms` / `fit_rig.ms` / `run_dump_bip.py` |
| 2026-10-27 | 产出 `bip_vs_smpl_on_video.mp4` 与一整套分析脚本 |
| 2026-10-27 | 定位 Biped 误差根因为中性姿势不匹配 |
| 2026-10-27 | 实测：保世界运动的修正无效；常数预畸变两个符号都变差 → 方案 A 否决，改走方案 B |
| 2026-10-28 | 定位髋部偏差根因：`.bip` 不存骨架，`loadBipFile` 用默认 1.64 m（髋宽 1.47 倍）；拟合只改 X 轴改不了髋宽 |
| 2026-10-28 | 定位手臂 21.8° 真凶：`mocap.elbowOrient = 0`；默认 point 时仅 0.49° |
| 2026-10-28 | 新增 `dump_bip_cmumode.ms`（CMU 方式直导），腿部残差 5.56% → 3.19% |
| 2026-10-28 | 新增 `bvh_export/ankle_yaw_fix.py` 脚掌 yaw 补偿：方向 18.3°/15.6° → 6.2°/5.9°，Toe 位置 6.7%/5.9% → 2.5%/2.3% |
| 2026-10-28 | 新增 `bip_export/run_cmumode.py` 一条命令流水线；`dump_bip_cmumode.ms` 改为参数驱动 |
| 2026-10-28 | 修正渲染映射：`Hips` 应映射到 `Bip001 Spine`（Biped 的 Pelvis 是更低 9.9 cm 的根骨），根部假误差 15.5% → 1.6% |
| 2026-10-28 | 定位手臂整体上移 10.2 cm 的根因：Biped 的 `Spine3 → L Clavicle` 骨长 17 cm，源 9.32 cm；CMU 同样（30.8%）（§8.8）|
| 2026-10-28 | 记录锁骨根结构差异：SMPL 双点（相距 8.56 cm）vs CMU 零长度单点；含重定向建议（§8.9）|
