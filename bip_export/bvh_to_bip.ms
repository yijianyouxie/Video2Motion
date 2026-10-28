-- ============================================================
-- bvh_to_bip.ms — 自动化: 把 clean BVH 转成 biped 的 .bip
-- v3: 用 .NET 文件 IO (System.IO.File), 硬编码路径, 逐步日志
--
-- 流程:
--   1. 单位设为米制
--   2. 创建 biped, 高度 1.64, 其余默认
--   3. Load Motion Capture File 加载 BVH (biped.loadMocapFile)
--   4. 根位置矫正
--   5. 导出 .bip
--
-- 调用: 3dsmax.exe -U MAXScript bvh_to_bip.ms
-- ============================================================

-- 尽早最小化 Max 主窗口 (Windows API, 不依赖 -silent 就能隐藏窗口)
try (
    local hwnd = windows.getMAXHWND()
    if hwnd != undefined do ( windows.sendMessage hwnd 0x0112 0xF020 0 )
) catch ()

netIO = dotNetClass "System.IO.File"
-- 项目根目录从脚本自身路径推导 (可移植: 部署到其他机器无需改路径)
scriptFull = getSourceFileName()
baseDir = substituteString ((pathConfig.removePathLeaf scriptFull) + "/") "\\" "/"
paramsFile = baseDir + "bvh_to_bip_params.txt"
resultFile = baseDir + "bvh_to_bip_result.txt"

fn logResult msg = (
    try ( netIO.AppendAllText resultFile (msg + "\n") ) catch ()
)

-- 解析 BVH 层级里每个关节的 OFFSET 长度 (米)。Biped 的骨长 = 该关节父节点的
-- 骨长，所以父骨的目标长度 = 子关节 OFFSET 的模。
fn bvhOffsets filePath = (
    local res = #()
    try (
        local fs = openFile filePath
        if fs != undefined do (
            local cur = ""
            local pend = false
            while not eof fs do (
                local s = trimLeft (readLine fs)
                if (findString s "JOINT ") == 1 or (findString s "ROOT ") == 1 do (
                    local sp = findString s " "
                    cur = trimLeft (substring s (sp + 1) 64)
                    pend = true
                )
                if pend and (findString s "OFFSET") == 1 do (
                    local v = filterString s " \t\r\n"
                    if v.count >= 4 do (
                        local dx = (v[2] as float)
                        local dy = (v[3] as float)
                        local dz = (v[4] as float)
                        append res #(cur, sqrt (dx*dx + dy*dy + dz*dz))
                    )
                    pend = false
                )
                if (findString s "MOTION") == 1 do exit
            )
            close fs
        )
    ) catch ()
    res
)

fn bvhOffsetLen tbl nm = (
    local r = 0.0
    for it in tbl where it[1] == nm do r = it[2]
    r
)

-- 兜底: 从 BVH 的 Frame Time 解析帧率 (仅当参数文件没有传 fps 时用)。
fn getBvhFps filePath = (
    local fps = 30
    try (
        local fs = openFile filePath
        if fs != undefined do (
            while not eof fs do (
                local ln = readLine fs
                local idx = findString ln "Frame Time:"
                if idx != undefined do (
                    local valStr = trimLeft (substring ln (idx + 11) ln.count)
                    local ft = valStr as float
                    if ft > 0.0 do fps = round (1.0 / ft)
                    exit
                )
            )
            close fs
        )
    ) catch ()
    return fps
)

logResult "script started"

-- ── 读取参数 ──
bvhPath = ""
outBip = ""
bvhFpsParam = 0   -- 第3行: 网页选择的帧率 (app.py 传入)
bvhSpineLinks = 3  -- 第4行: 网页选择的脊柱链接数 (默认3, 可选2/4)
bvhElbowOrient = 0  -- 第5行: 网页选择的肘朝向 (默认0=angle, 可选1=point)
try (
    local lines = netIO.ReadAllLines paramsFile
    bvhPath = trimLeft (lines[1] as string)   -- MAXScript 数组 1 起始
    outBip  = trimLeft (lines[2] as string)
    if lines.count >= 3 do (
        bvhFpsParam = try ((trimLeft (lines[3] as string)) as integer) catch (0)
    )
    if lines.count >= 4 do (
        bvhSpineLinks = try ((trimLeft (lines[4] as string)) as integer) catch (3)
    )
    if lines.count >= 5 do (
        bvhElbowOrient = try ((trimLeft (lines[5] as string)) as integer) catch (0)
    )
    logResult ("params: " + bvhPath)
) catch (
    logResult ("ERROR: params read failed: " + ((getCurrentException()) as string))
    quitMAX #noPrompt
)

try (
    -- 1. 单位 → 米制
    logResult "step1: units"
    try (units.SystemType = #meters) catch (logResult ("  units.SystemType err: " + ((getCurrentException()) as string)))
    units.DisplayType = #metric
    units.MetricType = #meters

    -- 1b. 帧率: 优先用 app.py 传入的 fps (网页选择), 否则从 BVH Frame Time 兜底。
    --     不设置的话 Max 默认 30fps 会把 15fps 动作播放快一倍。
    local bvhFps = bvhFpsParam
    if bvhFps <= 0 do bvhFps = getBvhFps bvhPath
    if bvhFps > 0 do ( frameRate = bvhFps )
    logResult ("step1b: fps=" + (bvhFps as string))

    -- 2. 创建 biped: 高 1.64, 带手臂, 其余默认
    sleep 2  -- 等 biped 系统就绪
    logResult "step2a: createNew"
    newBiped = biped.createNew 1.64 1.0 [0,0,0]
    logResult "step2b: controller"
    bipCtrl = newBiped.controller
    logResult "step2c: figureMode"
    bipCtrl.figureMode = false
    sleep 0.3
    logResult ("step2d: created " + newBiped.name)

    -- 3. 加载 BVH 运动捕捉
    --    Elbow 朝向由网页选择 (mocap.elbowOrient: 0=angle, 1=point)。Max 默认 point(=1) 用"肩-肘-腕"三角形平面
    --    反推肘绕上臂长轴的 twist，双臂高举时三点近共线 → 平面法向量退化 → twist 失控(6s 双臂扭曲根因)。
    --    angle 直接取 BVH 旋转数据里的 twist，对 SMPL→BVH 合成数据(旋转才是真值)更忠实、无奇异点。
    try (mocap.elbowOrient = bvhElbowOrient) catch (logResult ("  elbowOrient set err: " + ((getCurrentException()) as string)))
    logResult "step3: loadMocapFile"
    biped.loadMocapFile bipCtrl bvhPath
    logResult "  loaded"

    -- 3b. 加载后修改 spine links。加载前设无效(loadMocapFile 会重建并固定为4根),
    --     必须在 figureMode 下改; 4->3 末端动画基本重合, 4->2 会失真。
    if bvhSpineLinks >= 1 and bvhSpineLinks <= 5 do (
        logResult ("step3b: set spineLinks=" + (bvhSpineLinks as string))
        bipCtrl.figureMode = true
        sleep 0.3
        bipCtrl.spineLinks = bvhSpineLinks
        sleep 0.3
        bipCtrl.figureMode = false
        logResult "  spineLinks set"
    )

    -- 3c. 骨架拟合: 用 BVH 的 OFFSET 长度缩放 Biped 各骨, 让比例跟源骨架对齐。
    --     Biped 只能在该骨的 Figure Mode 下改长度, 且缩放作用在骨骼局部 X 轴。
    --     映射: Biped 骨 -> 它的子骨 -> BVH 里同位置的关节(用子关节的 OFFSET 作为目标长度)。
    try (
        logResult "step3c: fit rig"
        local offs = bvhOffsets bvhPath
        local FIT = #(
            #(" Pelvis", " Spine",  "Chest"),
            #(" Spine",  " Spine1", "Chest2"),
            #(" Spine1", " Spine2", "Chest3"),
            #(" Spine2", " Spine3", ""),          -- BVH 只有 3 节脊柱, 第 4 节缩成 3mm 残端
            #(" Spine3", " Neck",   "Neck"),
            #(" Neck",   " Head",   "Head"),
            #(" L Clavicle", " L UpperArm", "LeftShoulder"),
            #(" L UpperArm", " L Forearm",  "LeftElbow"),
            #(" L Forearm",  " L Hand",     "LeftWrist"),
            #(" R Clavicle", " R UpperArm", "RightShoulder"),
            #(" R UpperArm", " R Forearm",  "RightElbow"),
            #(" R Forearm",  " R Hand",     "RightWrist"),
            #(" L Thigh", " L Calf", "LeftKnee"),
            #(" L Calf",  " L Foot", "LeftAnkle"),
            #(" L Foot",  " L Toe0", "LeftToe"),
            #(" R Thigh", " R Calf", "RightKnee"),
            #(" R Calf",  " R Foot", "RightAnkle"),
            #(" R Foot",  " R Toe0", "RightToe")
        )
        bipCtrl.figureMode = true
        sleep 0.3
        local nFit = 0
        for it in FIT do (
            local p = getNodeByName (newBiped.name + it[1])
            local c = getNodeByName (newBiped.name + it[2])
            local target = if it[3] == "" then 0.003 else (bvhOffsetLen offs it[3])
            if p != undefined and c != undefined and target > 0.0 do (
                local cur = distance p.transform.pos c.transform.pos
                if cur > 0.001 do (
                    scale p [(target / cur), 1.0, 1.0]
                    nFit = nFit + 1
                )
            )
        )
        logResult ("  fitted " + (nFit as string) + " bones")
        -- .bip 只存动画, 不存骨架比例; 结构必须在 Figure Mode 下单独存成 .fig
        local outFig = (getFilenamePath outBip) + (getFilenameFile outBip) + ".fig"
        try (
            select newBiped
            biped.saveFigFile bipCtrl outFig
            logResult ("  fig saved: " + outFig)
        ) catch ( logResult ("  fig err: " + ((getCurrentException()) as string)) )
        bipCtrl.figureMode = false
        sleep 0.3
    ) catch ( logResult ("  fit err: " + ((getCurrentException()) as string)) )

    -- 4. 根位置矫正 (biped 骨骼用 .transform.pos 读取, 没有 .pos 属性)
    logResult "step4: fix root"
    pelvis = getNodeByName (newBiped.name + " Pelvis")
    if pelvis != undefined do (
        if (distance (pelvis.transform).pos [0,0,0]) > 20 do (
            biped.setTransform newBiped #pos [0,0,0.82] true
        )
    )
    logResult "  root fixed"

    -- 5. 保存 BIP
    logResult "step5: save BIP"
    animRange = animationRange
    startF = (animRange.start / TicksPerFrame) as integer
    endF = (animRange.end / TicksPerFrame) as integer
    biped.saveBipFileSegment bipCtrl outBip startF endF #keyPerFrame
    logResult "  saved"

    logResult "OK"
) catch (
    logResult ("ERROR: " + ((getCurrentException()) as string))
)

quitMAX #noPrompt
