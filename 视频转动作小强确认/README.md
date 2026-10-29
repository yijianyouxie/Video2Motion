# 视频转动作小强确认

2026-10-20 交给动画师确认效果的 `.bip` 样本，共 9 个，按源视频分三个目录。

## 目录与源视频

| 目录 | 源视频 |
|---|---|
| `视频1/` | last_year_summer |
| `视频2/` | man_dance |
| `视频3/` | women_dance |

## 命名规则

`<动作>_30_model<N>.bip`，其中 `N` 表示动作估计所用的模型：

| 后缀 | 来源 |
|---|---|
| `model1` | **GVHMR**（`bvh_out/GVHMR/demo/`）|
| `model2` | **motoncapture**（`bvh_out/motoncapture/`）|
| `model3` | **WHAM + smplify**（`bvh_out/WHAM/demo/*_smplify/`）|

## 文件清单与来源

| 文件 | 大小 | 源 `.bip`（已不入库）| 生成时间 |
|---|---:|---|---|
| `视频1/last_year_summer_30_model1.bip` | 1,038,776 | `bvh_out/GVHMR/demo/last_year_summer_30.bip` | 2026-10-20 14:53 |
| `视频1/last_year_summer_30_model3.bip` | 1,042,477 | `bvh_out/WHAM/demo/last_year_summer_30_smplify/last_year_summer_30.bip` | 2026-10-20 14:55 |
| `视频1/motion_30_model2.bip` | 1,037,208 | `bvh_out/motoncapture/last_year_summer/motion_30.bip` | 2026-10-20 15:23 |
| `视频2/man_dance_30_model1.bip` | 2,120,251 | `bvh_out/GVHMR/demo/man_dance_30.bip` | 2026-10-20 14:54 |
| `视频2/man_dance_30_model3.bip` | 2,042,203 | `bvh_out/WHAM/demo/man_dance_30_smplify/man_dance_30.bip` | 2026-10-20 14:55 |
| `视频2/motion_30_model2.bip` | 2,121,447 | `bvh_out/motoncapture/man_dance/motion_30.bip` | 2026-10-20 15:58 |
| `视频3/women_dance_30_model1.bip` | 2,768,119 | `bvh_out/GVHMR/demo/women_dance_30.bip` | 2026-10-20 14:54 |
| `视频3/women_dance_30_model3.bip` | 2,707,137 | `bvh_out/WHAM/demo/women_dance_30_smplify/women_dance_30.bip` | 2026-10-20 14:56 |
| `视频3/motion_30_model2.bip` | 2,767,357 | `bvh_out/motoncapture/women_dance/motion_30.bip` | 2026-10-20 16:31 |

> 源 `.bip` 与 BVH 已从仓库排除（`bvh_out/` 在 `.gitignore` 里），只保留这批交付样本。

## 生成时的脚本状态

| 项 | 值 |
|---|---|
| 调用器 | `bip_export/run_bvh_to_bip.py`（2026-10-20 14:52 版）|
| MAXScript | 从 Comfy-MotionCapture 复制的 `bvh_to_bip.ms`（与 `bip_export/bvh_to_bip.ms` 同源）|
| `fps` | **30** |
| `spineLinks` | **3** |
| `elbowOrient` | **0（angle）** |
| 输入预处理 | BVH 先 ÷100 转米制副本 `_work/<name>.bvh`，再送 Max |
| 输出 | `biped.saveBipFileSegment ... #keyPerFrame` |
| 骨架拟合 | ✗ 无（该功能 2026-10-27 才加入）|
| `.fig` | ✗ 无 |

这批文件是"两段式"产物：`createNew 1.64 → loadMocapFile → saveBipFile`。
`.bip` 只保存动画通道、不保存骨架比例，所以下游 `loadBipFile` 得到的永远是默认 1.64 m 骨架。

## 实测骨架特征（2026-10-29 复核）

| 文件组 | 帧数 | 骨骼数 | 大腿 | 小腿 | 脚掌 | 髋宽 | 髋宽/大腿 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 视频1（3 个）| 228 | 31 | 0.395181 | 0.395181 | 0.148135 | 0.158072 | 0.400 |
| 视频2（3 个）| 497 | 31 | 0.395181 | 0.395181 | 0.148135 | 0.158072 | 0.400 |
| 视频3（3 个）| 657 | 31 | 0.395181 | 0.395181 | 0.148135 | 0.158072 | 0.400 |

9 个文件骨架完全一致，且**大腿 = 小腿 = 0.395181**——这是 `createNew 1.64` 的默认比例，
说明 `.bip` 没有携带任何源骨架信息。读回时脊柱一律按默认 4 节重建（`.bip` 不存节数）。

## 当时的已知局限（均已在交接文档 §8 定位并修复）

| # | 问题 | 现状 |
|---|---|---|
| 1 | 髋宽 0.158（源 0.114，大 39%）| `.bip` 不存骨架，骨架拟合只改 X 轴、改不了髋宽；改用 `run_cmumode.py` 直导后髋宽 = 源值 |
| 2 | 手臂方向偏约 21.5° | 根因是 `mocap.elbowOrient = 0`；不设该参数（默认 point）时 0.49° |
| 3 | 脚掌朝向偏 18.3° / 15.6° | `bvh_export/ankle_yaw_fix.py` 补偿后 6.2° / 5.9° |
| 4 | 脊柱 3 节 | 直导后 4 节，骨长与源逐段一致 |

> **这批文件仅作历史对照，不代表当前流水线质量。**
> 当前推荐流程见 `bip_export/run_cmumode.py`（脚掌补偿 → 米制 → `loadMocapFile` → 直导）。

## 压缩包

`视频转动作小强确认.7z`（1.9 MB，2026-10-20 16:51）= 上述三个目录的打包，内容与本目录一致。
