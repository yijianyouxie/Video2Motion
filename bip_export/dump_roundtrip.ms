(
    local lg = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText lg "start\n"
    fn L m = ( nf.AppendAllText lg (m + "\n") )
    local BVH = "H:/MyProject/Video2Motion/bip_export/_work/gvhmr_man_dance_30.bvh"
    local BIP = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/_rt_plain.bip"
    local OUT = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/from_bip_roundtrip.csv"
    try (
        units.SystemType = #meters
        frameRate = 30
        -- 1) 干净转换并存 bip（不改 spineLinks、不拟合）
        local b1 = biped.createNew 1.64 1.0 [0,0,0]
        b1.controller.figureMode = false
        sleep 0.4
        biped.loadMocapFile b1.controller BVH
        sleep 0.5
        local ar = animationRange
        biped.saveBipFileSegment b1.controller BIP ((ar.start/TicksPerFrame) as integer) ((ar.end/TicksPerFrame) as integer) #keyPerFrame
        L ("saved plain bip, range " + (ar.start as string) + ".." + (ar.end as string))
        delete b1
        sleep 0.3
        -- 2) 读回
        local b2 = biped.createNew 1.64 1.0 [0,0,0]
        b2.controller.figureMode = false
        sleep 0.4
        biped.loadBipFile b2.controller BIP
        sleep 0.5
        local lt = getNodeByName "Bip001 L Thigh"
        local rt = getNodeByName "Bip001 R Thigh"
        local lc = getNodeByName "Bip001 L Calf"
        at time 0f (
            L ("rt thigh=" + ((distance lt.transform.pos lc.transform.pos) as string) +
               " hipw=" + ((distance lt.transform.pos rt.transform.pos) as string)) )
        local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
        L ("rt bones=" + (bones.count as string))
        local fs = createFile OUT
        format "frame,bone,x,y,z\n" to:fs
        local k = 0
        for t = animationRange.start to animationRange.end do (
            at time t (
                for o in bones do (
                    local q = o.transform.pos
                    local row = (k as string) + "," + o.name + "," + (q.x as string) + "," + (q.y as string) + "," + (q.z as string)
                    format "%\n" row to:fs ) )
            if (mod k 150) == 0 do L ("at " + (k as string))
            k = k + 1 )
        close fs
        L ("done frames=" + (k as string))
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
