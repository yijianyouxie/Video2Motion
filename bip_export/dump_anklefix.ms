(
    local lg = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText lg "start\n"
    fn L m = ( nf.AppendAllText lg (m + "\n") )
    local BVH = "H:/MyProject/Video2Motion/bip_export/_work/gvhmr_md_anklefix.bvh"
    local OUT = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/from_bip_anklefix.csv"
    try (
        units.SystemType = #meters
        frameRate = 30
        local b = biped.createNew 1.64 1.0 [0,0,0]
        b.controller.figureMode = false
        sleep 0.4
        biped.loadMocapFile b.controller BVH
        sleep 0.5
        L ("range " + (animationRange.start as string) + ".." + (animationRange.end as string))
        local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
        local fs = createFile OUT
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
