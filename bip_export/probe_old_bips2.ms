(
    local lg = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText lg "start\n"
    fn L m = ( nf.AppendAllText lg (m + "\n") )
    local BASE = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/_old_bips/"
    local FILES = #(#("m1", BASE + "m1.bip"), #("m3", BASE + "m3.bip"), #("m2", BASE + "m2.bip"))
    try (
        units.SystemType = #meters
        frameRate = 30
        for it in FILES do (
            local b = biped.createNew 1.64 1.0 [0,0,0]
            b.controller.figureMode = false
            sleep 0.4
            local ok = true
            try ( biped.loadBipFile b.controller it[2] )
                catch ( ok = false; L (it[1] + " ERR " + ((getCurrentException()) as string)) )
            sleep 0.5
            local a0 = animationRange.start
            local a1 = animationRange.end
            local nf2 = ((a1 - a0) / TicksPerFrame) as integer
            local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
            local sp = for o in bones where (matchPattern o.name pattern:"*Spine*") collect (substituteString o.name "Bip001 " "")
            local lt = getNodeByName "Bip001 L Thigh"
            local lc = getNodeByName "Bip001 L Calf"
            local lf = getNodeByName "Bip001 L Foot"
            local lto = getNodeByName "Bip001 L Toe0"
            local rt = getNodeByName "Bip001 R Thigh"
            L (it[1] + "  ok=" + (ok as string) + "  range=" + (a0 as string) + ".." + (a1 as string) + "  frames=" + (nf2 as string) + "  bones=" + (bones.count as string) + "  spine=" + (sp as string))
            at time 0f (
                L (it[1] + "  thigh=" + ((distance lt.transform.pos lc.transform.pos) as string) +
                   "  calf=" + ((distance lc.transform.pos lf.transform.pos) as string) +
                   "  foot=" + ((distance lf.transform.pos lto.transform.pos) as string) +
                   "  hipw=" + ((distance lt.transform.pos rt.transform.pos) as string)) )
            -- 采 6 个时间点，看骨盆 Z 与左脚趾长度是否变化
            local s = ""
            for k = 0 to 5 do (
                local t = a0 + ((a1 - a0) * k) / 5
                at time t (
                    s = s + ("|" + (formattedPrint (getNodeByName "Bip001 Pelvis").transform.pos.z format:"0.000") +
                             "/" + (formattedPrint (distance lto.transform.pos lf.transform.pos) format:"0.000")) )
            )
            L (it[1] + "  pelvisZ/toeLen " + s)
            delete b
            sleep 0.3
        )
        L "done"
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
