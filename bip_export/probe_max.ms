-- ============================================================
-- probe_max.ms — one session, many probes: characterise what
-- Biped's loadMocapFile does with the incoming motion, and
-- whether a Figure-Mode pose (matched to SMPL rest) survives
-- the load and changes the retarget result.
--
-- poseMode: 0 = default figure
--           1 = pose figure -> load
--           2 = pose figure -> load -> spineLinks -> re-pose
--           3 = load -> spineLinks -> pose (after)
-- All definitions at file top level (local fns are not visible
-- inside for-loop bodies).
-- ============================================================

logPath = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/probes/probe_log.txt"
nfIO = dotNetClass "System.IO.File"
nfIO.WriteAllText logPath "probe start\n"
fn L m = ( nfIO.AppendAllText logPath (m + "\n") )

global figTargets = fileIn "H:/MyProject/Video2Motion/bip_export/_work/probes/fig_targets.ms"
L ("figTargets loaded: " + (figTargets.count as string))

PDIR = "H:/MyProject/Video2Motion/bip_export/_work/probes/"
ODIR = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/probes/"
REALBVH = "H:/MyProject/Video2Motion/bip_export/_work/gvhmr_man_dance_30.bvh"

PROBES = #(
    #("orig_real",    PDIR + "orig_real.bvh",    ODIR + "out_orig_real.csv",    498, 0),
    #("ren3_real12",  PDIR + "ren3_real12.bvh",  ODIR + "out_ren3_real12.csv",  12,  0),
    #("ren3_chest2",  PDIR + "ren3_chest2.bvh",  ODIR + "out_ren3_chest2.csv",  12,  0),
    #("orig_chest2",  PDIR + "orig_chest2.bvh",  ODIR + "out_orig_chest2.csv",  12,  0)
)
)

fn fromToQuat a b = (
    -- manual from-to quaternion (quatFromDir is not available in Max 2016)
    local d = amax #((amin #((dot a b), 1.0)), -1.0)
    local v = cross a b
    if (length v) < 1e-6 then (
        if d > 0 then (quat 0.0 0.0 0.0 1.0)
        else (
            local ax = if (abs a.x) < 0.9 then (normalize (cross a [1,0,0])) else (normalize (cross a [0,1,0]))
            quat (ax.x * 0.70710678) (ax.y * 0.70710678) (ax.z * 0.70710678) 0.70710678
        )
    ) else (
        local v2 = normalize v
        local w = sqrt ((1.0 + d) / 2.0)
        local s = sqrt ((1.0 - d) / 2.0)
        quat (v2.x * s) (v2.y * s) (v2.z * s) w
    )
)

fn logDirs logTag = (
    for tg in figTargets do (
        local n = getNodeByName tg[1]
        local c = getNodeByName tg[2]
        if n != undefined and c != undefined then (
            local d = normalize (c.transform.pos - n.transform.pos)
            local s1 = (formattedPrint d.x format:"6.3f") + " " + (formattedPrint d.y format:"6.3f") + " " + (formattedPrint d.z format:"6.3f")
            local s2 = (formattedPrint tg[3].x format:"6.3f") + " " + (formattedPrint tg[3].y format:"6.3f") + " " + (formattedPrint tg[3].z format:"6.3f")
            L (logTag + " " + tg[1] + " dir [" + s1 + "] want [" + s2 + "]")
        ) else (
            L (logTag + " " + tg[1] + " MISSING")
        )
    )
)

fn poseFig logTag = (
    local first = true
    for tg in figTargets do (
        local n = getNodeByName tg[1]
        local c = getNodeByName tg[2]
        if n != undefined and c != undefined then (
            local dCur = normalize (c.transform.pos - n.transform.pos)
            local dTgt = normalize tg[3]
            if first do ( L ("  posing " + tg[1] + " dCur " + (dCur as string)); first = false )
            local q = fromToQuat dCur dTgt
            if first do L "  never"
            preRotate n q
            if (tg[1] == "Bip001 Spine") do L "  first preRotate done"
            local dNew = normalize (c.transform.pos - n.transform.pos)
            local err = acos (amax #((amin #((dot dNew dTgt), 1.0)), -1.0))
            if err > 5.0 do L (logTag + " WARN " + tg[1] + " err " + (err as string))
        ) else (
            L (logTag + " MISSING " + tg[1])
        )
    )
)

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
fn bvhOffsetLen tbl nm = ( local r = 0.0; for it in tbl where it[1] == nm do r = it[2]; r )
bvhOffsets_ = bvhOffsets (PDIR + "zero.bvh")

fn fitRig b = (
    local FIT = #(
        #(" Pelvis", " Spine",  "Chest"), #(" Spine",  " Spine1", "Chest2"),
        #(" Spine1", " Spine2", "Chest3"), #(" Spine2", " Spine3", ""),
        #(" Spine3", " Neck",   "Neck"),   #(" Neck",   " Head",   "Head"),
        #(" L Clavicle", " L UpperArm", "LeftShoulder"), #(" L UpperArm", " L Forearm", "LeftElbow"),
        #(" L Forearm",  " L Hand",     "LeftWrist"),
        #(" R Clavicle", " R UpperArm", "RightShoulder"), #(" R UpperArm", " R Forearm", "RightElbow"),
        #(" R Forearm",  " R Hand",     "RightWrist"),
        #(" L Thigh", " L Calf", "LeftKnee"), #(" L Calf", " L Foot", "LeftAnkle"),
        #(" L Foot",  " L Toe0", "LeftToe"),
        #(" R Thigh", " R Calf", "RightKnee"), #(" R Calf", " R Foot", "RightAnkle"),
        #(" R Foot",  " R Toe0", "RightToe")
    )
    b.controller.figureMode = true
    sleep 0.2
    local nFit = 0
    for it in FIT do (
        local p = getNodeByName (b.name + it[1])
        local c = getNodeByName (b.name + it[2])
        local target = if it[3] == "" then 0.003 else (bvhOffsetLen bvhOffsets_ it[3])
        if p != undefined and c != undefined and target > 0.0 do (
            local cur = distance p.transform.pos c.transform.pos
            if cur > 0.001 do ( scale p [(target / cur), 1.0, 1.0]; nFit = nFit + 1 )
        )
    )
    b.controller.figureMode = false
    sleep 0.2
    L ("  fitted " + (nFit as string))
)

fn dumpPose csvPath nframes = (
    local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
    local fs = createFile csvPath
    format "frame,bone,x,y,z\n" to:fs
    local lastT = (nframes - 1) * 1f
    local k = 0
    for t = 0f to lastT do (
        at time t (
            for o in bones do (
                local q = o.transform.pos
                format "%,%,%,%,%\n" (k as string) o.name (q.x as string) (q.y as string) (q.z as string) to:fs
            )
        )
        k = k + 1
    )
    close fs
    L ("  dumped " + (k as string) + " frames")
)

for pr in PROBES do (
    local name = pr[1]
    try (
        L ("=== probe " + name + " ===")
        resetMaxFile #noPrompt
        L "  reset ok"
        sleep 1
        units.SystemType = #meters
        frameRate = 30
        try (mocap.elbowOrient = 0) catch (L "  elbowOrient err")
        sleep 2
        L "  creating biped"
        local b = biped.createNew 1.64 1.0 [0,0,0]
        local ctrl = b.controller
        L "  biped created"

        if pr[5] == 1 or pr[5] == 2 do (
            ctrl.figureMode = true
            sleep 0.3
            L "  figureMode on, posing"
            poseFig (name + "/pose1")
            L "  pose1 done"
            ctrl.figureMode = false
            sleep 0.3
            logDirs (name + "/check1")
        )
        L "  loadMocapFile"
        biped.loadMocapFile ctrl pr[2]
        L ("  loaded, range " + (animationRange.start as string) + ".." + (animationRange.end as string))

        ctrl.figureMode = true
        sleep 0.2
        ctrl.spineLinks = 3
        sleep 0.2
        if pr[5] == 2 do ( poseFig (name + "/repose"); logDirs (name + "/check2") )
        if pr[5] == 3 do ( poseFig (name + "/pose-after"); logDirs (name + "/check3") )
        if pr[5] == 1 do ( logDirs (name + "/check-after-load") )
        ctrl.figureMode = false
        sleep 0.2

        fitRig b
        dumpPose pr[3] pr[4]
    ) catch (
        L ("ERROR " + name + ": " + ((getCurrentException()) as string))
    )
)
L "ALL DONE"
quitMAX #noPrompt
