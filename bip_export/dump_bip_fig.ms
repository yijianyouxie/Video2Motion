(
    local lg = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local outPath = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/from_bip_fig.csv"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText lg "start\n"
    fn L m = ( nf.AppendAllText lg (m + "\n") )
    local FIG = "H:/MyProject/Video2Motion/bvh_out/GVHMR/demo/man_dance_30.fig"
    local BIP = "H:/MyProject/Video2Motion/bvh_out/GVHMR/demo/man_dance_30.bip"
    try (
        units.SystemType = #meters
        frameRate = 30
        local b = biped.createNew 1.64 1.0 [0,0,0]
        b.controller.figureMode = false
        sleep 0.4
        b.controller.figureMode = true
        sleep 0.5
        biped.loadFigFile b.controller FIG
        sleep 0.5
        b.controller.figureMode = false
        sleep 0.5
        biped.loadBipFile b.controller BIP
        sleep 0.5
        L ("range " + (animationRange.start as string) + ".." + (animationRange.end as string))
        local lt = getNodeByName "Bip001 L Thigh"
        local rt = getNodeByName "Bip001 R Thigh"
        local lc = getNodeByName "Bip001 L Calf"
        at time 0f (
            L ("check: thigh=" + ((distance lt.transform.pos lc.transform.pos) as string) +
               " hipw=" + ((distance lt.transform.pos rt.transform.pos) as string))
        )
        local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
        local fs = createFile outPath
        format "frame,bone,x,y,z\n" to:fs
        local k = 0
        for t = 0f to 497f do (
            at time t (
                for o in bones do (
                    local q = o.transform.pos
                    local row = (k as string) + "," + o.name
                    row = row + "," + (q.x as string) + "," + (q.y as string) + "," + (q.z as string)
                    format "%\n" row to:fs ) )
            if (mod k 150) == 0 do L ("at " + (k as string))
            k = k + 1 )
        close fs
        L ("done frames=" + (k as string))
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
