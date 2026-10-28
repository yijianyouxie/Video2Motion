(
    local logPath = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local outPath = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/fit.csv"
    local bipPath = "H:/MyProject/Video2Motion/bvh_out/GVHMR/demo/man_dance_30.bip"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText logPath "start\n"
    fn L m = ( nf.AppendAllText logPath (m + "\n") )
    fn lenA a b = ( distance (getNodeByName a).transform.pos (getNodeByName b).transform.pos )
    local T = #(
        #("Bip001 Pelvis","Bip001 Spine", 10.80),
        #("Bip001 Spine","Bip001 Spine1", 12.79),
        #("Bip001 Spine1","Bip001 Spine2", 5.46),
        #("Bip001 Spine2","Bip001 Spine3", 0.30),
        #("Bip001 Spine3","Bip001 Neck", 16.30),
        #("Bip001 Neck","Bip001 Head", 16.62),
        #("Bip001 L Clavicle","Bip001 L UpperArm", 12.31),
        #("Bip001 L UpperArm","Bip001 L Forearm", 27.20),
        #("Bip001 L Forearm","Bip001 L Hand", 25.75),
        #("Bip001 L Thigh","Bip001 L Calf", 40.59),
        #("Bip001 L Calf","Bip001 L Foot", 42.51),
        #("Bip001 L Foot","Bip001 L Toe0", 13.97),
        #("Bip001 R Clavicle","Bip001 R UpperArm", 12.31),
        #("Bip001 R UpperArm","Bip001 R Forearm", 27.20),
        #("Bip001 R Forearm","Bip001 R Hand", 25.75),
        #("Bip001 R Thigh","Bip001 R Calf", 40.59),
        #("Bip001 R Calf","Bip001 R Foot", 42.51),
        #("Bip001 R Foot","Bip001 R Toe0", 13.97)
    )
    try (
        units.SystemType = #meters
        frameRate = 30
        local b = biped.createNew 1.64 1.0 [0,0,0]
        b.controller.figureMode = false
        biped.loadBipFile b.controller bipPath
        sliderTime = 0f
        L ("before: upperarm->forearm " + (lenA "Bip001 L UpperArm" "Bip001 L Forearm") as string)
        L ("before: forearm->hand     " + (lenA "Bip001 L Forearm" "Bip001 L Hand") as string)
        L ("before: hip width         " + (lenA "Bip001 L Thigh" "Bip001 R Thigh") as string)

        b.controller.figureMode = true
        sleep 0.3
        for it = 1 to 3 do (
            for t in T do (
                local p = getNodeByName t[1]
                local c = getNodeByName t[2]
                local cur = distance p.transform.pos c.transform.pos
                if cur > 0.01 do (
                    local r = (t[3] / 100.0) / cur
                    scale p [r, 1.0, 1.0]
                )
            )
            sleep 0.1
            L ("pass " + (it as string) + " done")
        )
        b.controller.figureMode = false
        sleep 0.3
        sliderTime = 0f
        L "--- after ---"
        for t in T do (
            local cur = distance (getNodeByName t[1]).transform.pos (getNodeByName t[2]).transform.pos
            L (t[1] + "->" + t[2] + "  target " + (t[3] as string) + "  actual " + (cur*100.0) as string)
        )
        L ("after: forearm->hand " + (lenA "Bip001 L Forearm" "Bip001 L Hand") as string)
        L ("after: hip width     " + (lenA "Bip001 L Thigh" "Bip001 R Thigh") as string)

        local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
        local fs = createFile outPath
        format "bone,x,y,z\n" to:fs
        for o in bones do (
            local q = o.transform.pos
            local row = o.name
            row = row + "," + (q.x as string)
            row = row + "," + (q.y as string)
            row = row + "," + (q.z as string)
            format "%\n" row to:fs
        )
        close fs
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    L "done"
    quitMAX #noPrompt
)
