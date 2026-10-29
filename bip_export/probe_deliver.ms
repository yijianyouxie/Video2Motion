(
    local lg = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local outPath = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/deliver_probe.csv"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText lg "start\n"
    fn L m = ( nf.AppendAllText lg (m + "\n") )
    local BASE = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/_deliver/"
    local FILES = #(#("v1_m1","v1_m1.bip"),#("v1_m3","v1_m3.bip"),#("v1_m2","v1_m2.bip"),
                    #("v2_m1","v2_m1.bip"),#("v2_m3","v2_m3.bip"),#("v2_m2","v2_m2.bip"),
                    #("v3_m1","v3_m1.bip"),#("v3_m3","v3_m3.bip"),#("v3_m2","v3_m2.bip"))
    local fs = createFile outPath
    format "tag,frames,bones,spine,thigh,calf,foot,hipw,ratio\n" to:fs
    try (
        units.SystemType = #meters
        frameRate = 30
        for it in FILES do (
            local b = biped.createNew 1.64 1.0 [0,0,0]
            b.controller.figureMode = false
            sleep 0.3
            biped.loadBipFile b.controller (BASE + it[2])
            sleep 0.4
            local a0 = animationRange.start
            local a1 = animationRange.end
            local nfr = (((a1 - a0) / TicksPerFrame) as integer)
            local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
            local sp = for o in bones where (matchPattern o.name pattern:"*Spine*") collect 1
            local lt = getNodeByName "Bip001 L Thigh"
            local lc = getNodeByName "Bip001 L Calf"
            local lf = getNodeByName "Bip001 L Foot"
            local lto = getNodeByName "Bip001 L Toe0"
            local rt = getNodeByName "Bip001 R Thigh"
            local th = distance lt.transform.pos lc.transform.pos
            local cf = distance lc.transform.pos lf.transform.pos
            local ft = distance lf.transform.pos lto.transform.pos
            local hw = distance lt.transform.pos rt.transform.pos
            format "%,%,%,%,%,%,%,%,%\n" it[1] nfr bones.count sp.count th cf ft hw (hw/th) to:fs
            L (it[1] + " frames=" + (nfr as string) + " bones=" + (bones.count as string) + " spine=" + (sp.count as string))
            delete b
            sleep 0.2
        )
        L "done"
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    close fs
    quitMAX #noPrompt
)
