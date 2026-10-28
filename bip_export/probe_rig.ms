(
    local logPath = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local outPath = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/configs.csv"
    local bipPath = "H:/MyProject/Video2Motion/bvh_out/GVHMR/demo/man_dance_30.bip"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText logPath "start\n"
    fn L m = ( nf.AppendAllText logPath (m + "\n") )
    local fs = createFile outPath
    format "config,bone,x,y,z\n" to:fs
    fn dumpCfg tag = (
        local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
        at time 0f (
            for o in bones do (
                local q = o.transform.pos
                local row = tag
                row = row + "," + o.name
                row = row + "," + (q.x as string)
                row = row + "," + (q.y as string)
                row = row + "," + (q.z as string)
                format "%\n" row to:fs
            )
        )
        local sp = for o in bones where (matchPattern o.name pattern:"*Spine*") collect o.name
        L (tag + " bones=" + (bones.count as string) + "  spine=" + (sp as string))
    )
    fn makeBip = (
        local b = biped.createNew 1.64 1.0 [0,0,0]
        b.controller.figureMode = false
        biped.loadBipFile b.controller bipPath
        b
    )
    try (
        units.SystemType = #meters
        frameRate = 30

        local bA = makeBip()
        dumpCfg "A_base"
        local ua = getNodeByName "Bip001 L UpperArm"
        local fa = getNodeByName "Bip001 L Forearm"
        L ("A upperarm->forearm = " + (distance ua.transform.pos fa.transform.pos) as string)
        delete bA

        local bC = makeBip()
        bC.controller.figureMode = true
        sleep 0.2
        bC.controller.spineLinks = 2
        sleep 0.2
        bC.controller.figureMode = false
        sleep 0.2
        dumpCfg "C_spine2"
        delete bC

        for ax in #(1, 2, 3) do (
            local bD = makeBip()
            bD.controller.figureMode = true
            sleep 0.2
            local s = [1.0,1.0,1.0]
            s[ax] = 1.25
            scale $'Bip001 L UpperArm' s
            sleep 0.2
            bD.controller.figureMode = false
            sleep 0.2
            dumpCfg ("D_scale" + (ax as string))
            local ua2 = getNodeByName "Bip001 L UpperArm"
            local fa2 = getNodeByName "Bip001 L Forearm"
            L ("axis " + (ax as string) + " upperarm->forearm = " + (distance ua2.transform.pos fa2.transform.pos) as string)
            delete bD
        )
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    close fs
    L "done"
    quitMAX #noPrompt
)
