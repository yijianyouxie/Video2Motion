(
    local lg = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText lg "start\n"
    fn L m = ( nf.AppendAllText lg (m + "\n") )
    local BVH = "H:/MyProject/Video2Motion/bip_export/_work/gvhmr_man_dance_30.bvh"
    local OUT0 = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/from_bip_knee0.csv"
    local OUT1 = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/from_bip_knee1.csv"
    fn dumpAll tag outPath = (
        local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
        local fs = createFile outPath
        format "frame,bone,x,y,z\n" to:fs
        local k = 0
        for t = animationRange.start to animationRange.end do (
            at time t (
                for o in bones do (
                    local q = o.transform.pos
                    format "%\n" ((k as string) + "," + o.name + "," + (q.x as string) + "," + (q.y as string) + "," + (q.z as string)) to:fs ) )
            if (mod k 200) == 0 do L (tag + " at " + (k as string))
            k = k + 1 )
        close fs
        L (tag + " frames=" + (k as string))
    )
    try (
        units.SystemType = #meters
        frameRate = 30
        for cfg in #(#("knee1_point", 1, OUT1), #("knee0_angle", 0, OUT0)) do (
            try ( mocap.kneeOrient = cfg[2] ) catch ( L ("kneeOrient set err") )
            L (cfg[1] + " kneeOrient=" + (mocap.kneeOrient as string))
            local b = biped.createNew 1.64 1.0 [0,0,0]
            b.controller.figureMode = false
            sleep 0.4
            biped.loadMocapFile b.controller BVH
            sleep 0.5
            dumpAll cfg[1] cfg[3]
            delete b
            sleep 0.3
        )
        L "done"
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
