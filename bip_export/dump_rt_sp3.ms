(
    local lg = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText lg "start\n"
    fn L m = ( nf.AppendAllText lg (m + "\n") )
    local BVH = "H:/MyProject/Video2Motion/bip_export/_work/gvhmr_man_dance_30.bvh"
    local BIP = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/_rt_sp3.bip"
    local OUT = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/from_bip_rt_sp3.csv"
    try (
        units.SystemType = #meters
        frameRate = 30
        local b1 = biped.createNew 1.64 1.0 [0,0,0]
        b1.controller.figureMode = false
        sleep 0.4
        biped.loadMocapFile b1.controller BVH
        sleep 0.5
        b1.controller.figureMode = true
        sleep 0.4
        b1.controller.spineLinks = 3
        sleep 0.4
        b1.controller.figureMode = false
        sleep 0.4
        local ar = animationRange
        biped.saveBipFileSegment b1.controller BIP ((ar.start/TicksPerFrame) as integer) ((ar.end/TicksPerFrame) as integer) #keyPerFrame
        L "saved sp3 bip"
        delete b1
        sleep 0.3
        local b2 = biped.createNew 1.64 1.0 [0,0,0]
        b2.controller.figureMode = false
        sleep 0.4
        biped.loadBipFile b2.controller BIP
        sleep 0.5
        local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
        L ("rt_sp3 bones=" + (bones.count as string) + "  spine=" + ((for o in bones where (matchPattern o.name pattern:"*Spine*") collect (substituteString o.name "Bip001 " "")) as string))
        local fs = createFile OUT
        format "frame,bone,x,y,z\n" to:fs
        local k = 0
        for t = animationRange.start to animationRange.end do (
            at time t (
                for o in bones do (
                    local q = o.transform.pos
                    format "%\n" ((k as string) + "," + o.name + "," + (q.x as string) + "," + (q.y as string) + "," + (q.z as string)) to:fs ) )
            if (mod k 150) == 0 do L ("at " + (k as string))
            k = k + 1 )
        close fs
        L ("done frames=" + (k as string))
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
