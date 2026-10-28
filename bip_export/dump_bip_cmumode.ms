-- dump_bip_cmumode.ms
-- 与 cmu_dump.ms 相同的处理：createNew -> loadMocapFile -> 逐帧导出
-- 不修改 spineLinks、不做骨架拟合、不保存/加载 .fig
-- 输入 BVH 由 dump_cmumode_params.txt 指定（第1行 BVH，第2行 CSV，第3行 fps）
(
    local logPath = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local paramFile = "H:/MyProject/Video2Motion/bip_export/dump_cmumode_params.txt"
    local bvhPath = "H:/MyProject/Video2Motion/bip_export/_work/gvhmr_man_dance_30.bvh"
    local outPath = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/from_bip.csv"
    local fps = 30
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText logPath "start\n"
    fn L m = ( nf.AppendAllText logPath (m + "\n") )
    try (
        local lines = nf.ReadAllLines paramFile   -- MAXScript 对 .NET 数组用 1-based 下标
        if lines.count >= 1 do bvhPath = trimLeft (lines[1] as string)
        if lines.count >= 2 do outPath = trimLeft (lines[2] as string)
        if lines.count >= 3 do fps = try ((trimLeft (lines[3] as string)) as integer) catch (30)
    ) catch ( L "params missing, use defaults" )

    try (
        units.SystemType = #meters
        frameRate = fps
        L ("bvh=" + bvhPath)
        L ("out=" + outPath)
        local b = biped.createNew 1.64 1.0 [0,0,0]
        b.controller.figureMode = false
        sleep 0.4
        biped.loadMocapFile b.controller bvhPath
        sleep 0.5
        L ("range " + (animationRange.start as string) + ".." + (animationRange.end as string))
        local lt = getNodeByName "Bip001 L Thigh"
        local rt = getNodeByName "Bip001 R Thigh"
        local lc = getNodeByName "Bip001 L Calf"
        at time 0f (
            L ("check thigh=" + ((distance lt.transform.pos lc.transform.pos) as string) +
               " hipw=" + ((distance lt.transform.pos rt.transform.pos) as string)) )
        local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
        L ("bones=" + (bones.count as string))
        local fs = createFile outPath
        format "frame,bone,x,y,z\n" to:fs
        local k = 0
        for t = animationRange.start to animationRange.end do (
            at time t (
                for o in bones do (
                    local q = o.transform.pos
                    format "%\n" ((k as string) + "," + o.name + "," + (q.x as string) + "," + (q.y as string) + "," + (q.z as string)) to:fs ) )
            if (mod k 200) == 0 do L ("at " + (k as string))
            k = k + 1 )
        close fs
        L ("done frames=" + (k as string))
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
