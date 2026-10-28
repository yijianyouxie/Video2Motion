(
    local logPath = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local outPath = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/cmu_01_sp4.csv"
    local bvhPath = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/cmu_01_clean.bvh"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText logPath "start\n"
    fn L m = ( nf.AppendAllText logPath (m + "\n") )
    try (
        units.SystemType = #meters
        frameRate = 120
        local b = biped.createNew 1.64 1.0 [0,0,0]
        b.controller.figureMode = false
        sleep 0.3
        biped.loadMocapFile b.controller bvhPath
        b.controller.figureMode = true
        sleep 0.3
        b.controller.spineLinks = 4
        sleep 0.3
        b.controller.figureMode = false
        sleep 0.3
        L ("range " + (animationRange.start as string) + ".." + (animationRange.end as string))
        local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
        L ("bones=" + (bones.count as string))
        for o in bones do L ("  " + o.name)
        local fs = createFile outPath
        format "frame,bone,x,y,z\n" to:fs
        local k = 0
        local e = animationRange.end
        for t = animationRange.start to e do (
            at time t (
                for o in bones do (
                    local q = o.transform.pos
                    local row = (k as string) + "," + o.name
                    row = row + "," + (q.x as string) + "," + (q.y as string) + "," + (q.z as string)
                    format "%\n" row to:fs ) )
            if (mod k 400) == 0 do L ("at " + (k as string))
            k = k + 1 )
        close fs
        L ("done " + (k as string))
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
