(
    local lg = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText lg "start\n"
    fn L m = ( nf.AppendAllText lg (m + "\n") )

    local BIP = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/man_dance_30_comfy.bip"
    local BVH = "H:/MyProject/Video2Motion/bip_export/_work/gvhmr_man_dance_30.bvh"
    local OUTA = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/from_bip_comfy_bip.csv"
    local OUTB = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/from_bip_comfy_direct.csv"

    fn dumpAll tag outPath = (
        local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
        L (tag + " bones=" + (bones.count as string))
        local fs = createFile outPath
        format "frame,bone,x,y,z\n" to:fs
        local k = 0
        for t = animationRange.start to animationRange.end do (
            at time t (
                for o in bones do (
                    local q = o.transform.pos
                    local row = (k as string) + "," + o.name
                    row = row + "," + (q.x as string) + "," + (q.y as string) + "," + (q.z as string)
                    format "%\n" row to:fs ) )
            if (mod k 150) == 0 do L (tag + " at " + (k as string))
            k = k + 1 )
        close fs
        L (tag + " frames=" + (k as string))
    )

    try (
        units.SystemType = #meters
        frameRate = 30

        -- A: 直接读 comfy 生成的 .bip
        local b1 = biped.createNew 1.64 1.0 [0,0,0]
        b1.controller.figureMode = false
        sleep 0.4
        biped.loadBipFile b1.controller BIP
        sleep 0.5
        L ("A range " + (animationRange.start as string) + ".." + (animationRange.end as string))
        local lt1 = getNodeByName "Bip001 L Thigh"
        local rt1 = getNodeByName "Bip001 R Thigh"
        local lc1 = getNodeByName "Bip001 L Calf"
        at time 0f (
            L ("A thigh=" + ((distance lt1.transform.pos lc1.transform.pos) as string) +
               " hipw=" + ((distance lt1.transform.pos rt1.transform.pos) as string)) )
        dumpAll "A" OUTA
        delete b1

        -- B: 复现 comfy 的处理，但不落 .bip
        local b2 = biped.createNew 1.64 1.0 [0,0,0]
        b2.controller.figureMode = false
        sleep 0.4
        try ( mocap.elbowOrient = 0; L "B elbowOrient=0 ok" ) catch ( L "B elbowOrient err" )
        biped.loadMocapFile b2.controller BVH
        sleep 0.5
        b2.controller.figureMode = true
        sleep 0.4
        b2.controller.spineLinks = 3
        sleep 0.4
        b2.controller.figureMode = false
        sleep 0.4
        local pel = getNodeByName (b2.name + " Pelvis")
        if pel != undefined and (distance pel.transform.pos [0,0,0]) > 20 do (
            biped.setTransform b2 #pos [0,0,0.82] true
            L "B root fixed" )
        sleep 0.3
        local lt2 = getNodeByName "Bip001 L Thigh"
        local rt2 = getNodeByName "Bip001 R Thigh"
        local lc2 = getNodeByName "Bip001 L Calf"
        at time 0f (
            L ("B thigh=" + ((distance lt2.transform.pos lc2.transform.pos) as string) +
               " hipw=" + ((distance lt2.transform.pos rt2.transform.pos) as string)) )
        dumpAll "B" OUTB

        L "done"
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
