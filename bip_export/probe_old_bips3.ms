(
    local lg = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText lg "start\n"
    fn L m = ( nf.AppendAllText lg (m + "\n") )
    local BASE = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/_old_bips/"
    local FILES = #(#("m1", BASE + "m1.bip"), #("m3", BASE + "m3.bip"), #("m2", BASE + "m2.bip"))
    fn seg a b = ( distance (getNodeByName a).transform.pos (getNodeByName b).transform.pos )
    try (
        units.SystemType = #meters
        frameRate = 30
        for it in FILES do (
            local b = biped.createNew 1.64 1.0 [0,0,0]
            b.controller.figureMode = false
            sleep 0.4
            biped.loadBipFile b.controller it[2]
            sleep 0.5
            local a0 = animationRange.start
            local a1 = animationRange.end
            at time a0 (
                local s1 = "  spineLen Pelvis>Spine=" + ((seg "Bip001 Pelvis" "Bip001 Spine") as string)
                s1 = s1 + " Spine>Spine1=" + ((seg "Bip001 Spine" "Bip001 Spine1") as string)
                s1 = s1 + " Spine1>Spine2=" + ((seg "Bip001 Spine1" "Bip001 Spine2") as string)
                s1 = s1 + " Spine2>Spine3=" + ((seg "Bip001 Spine2" "Bip001 Spine3") as string)
                s1 = s1 + " Spine3>Neck=" + ((seg "Bip001 Spine3" "Bip001 Neck") as string)
                L (it[1] + s1)
            )
            -- 6 个时刻的骨盆 Z 与左脚趾长度
            local s2 = ""
            for k = 0 to 5 do (
                local t = a0 + ((a1 - a0) * k) / 5
                local pz = 0.0
                local tl = 0.0
                at time t ( pz = (getNodeByName "Bip001 Pelvis").transform.pos.z; tl = seg "Bip001 L Foot" "Bip001 L Toe0" )
                s2 = s2 + "  [" + ((k*100/5) as string) + "%] z=" + ((formattedPrint pz format:"0.0000") as string) + " toe=" + ((formattedPrint tl format:"0.0000") as string)
            )
            L (it[1] + s2)
            delete b
            sleep 0.3
        )
        L "done"
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
