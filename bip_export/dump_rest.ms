(
    local logPath = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local outPath = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/rest.csv"
    local bipPath = "H:/MyProject/Video2Motion/bvh_out/GVHMR/demo/man_dance_30.bip"
    local bvhPath = "H:/MyProject/Video2Motion/bip_export/_work/gvhmr_man_dance_30.bvh"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText logPath "start\n"
    fn L m = ( nf.AppendAllText logPath (m + "\n") )
    fn bvhOffsets filePath = (
        local res = #()
        try (
            local fs = openFile filePath
            if fs != undefined do (
                local cur = ""; local pend = false
                while not eof fs do (
                    local s = trimLeft (readLine fs)
                    if (findString s "JOINT ") == 1 or (findString s "ROOT ") == 1 do (
                        local sp = findString s " "
                        cur = trimLeft (substring s (sp + 1) 64); pend = true
                    )
                    if pend and (findString s "OFFSET") == 1 do (
                        local v = filterString s " \t\r\n"
                        if v.count >= 4 do (
                            local dx=(v[2] as float); local dy=(v[3] as float); local dz=(v[4] as float)
                            append res #(cur, sqrt(dx*dx+dy*dy+dz*dz))
                        )
                        pend = false
                    )
                    if (findString s "MOTION") == 1 do exit
                )
                close fs
            )
        ) catch ()
        res
    )
    fn bvhOffsetLen tbl nm = ( local r=0.0; for it in tbl where it[1]==nm do r=it[2]; r )
    local FIT = #(#(" Pelvis"," Spine","Chest"),#(" Spine"," Spine1","Chest2"),
        #(" Spine1"," Spine2","Chest3"),#(" Spine2"," Spine3",""),
        #(" Spine3"," Neck","Neck"),#(" Neck"," Head","Head"),
        #(" L Clavicle"," L UpperArm","LeftShoulder"),#(" L UpperArm"," L Forearm","LeftElbow"),
        #(" L Forearm"," L Hand","LeftWrist"),
        #(" R Clavicle"," R UpperArm","RightShoulder"),#(" R UpperArm"," R Forearm","RightElbow"),
        #(" R Forearm"," R Hand","RightWrist"),
        #(" L Thigh"," L Calf","LeftKnee"),#(" L Calf"," L Foot","LeftAnkle"),#(" L Foot"," L Toe0","LeftToe"),
        #(" R Thigh"," R Calf","RightKnee"),#(" R Calf"," R Foot","RightAnkle"),#(" R Foot"," R Toe0","RightToe"))
    try (
        units.SystemType = #meters
        frameRate = 30
        local b = biped.createNew 1.64 1.0 [0,0,0]
        b.controller.figureMode = false
        biped.loadBipFile b.controller bipPath
        local offs = bvhOffsets bvhPath
        b.controller.figureMode = true
        sleep 0.3
        b.controller.spineLinks = 3
        sleep 0.2
        for it in FIT do (
            local p = getNodeByName (b.name + it[1])
            local c = getNodeByName (b.name + it[2])
            local target = if it[3] == "" then 0.003 else (bvhOffsetLen offs it[3])
            if p != undefined and c != undefined and target > 0.0 do (
                local cur = distance p.transform.pos c.transform.pos
                if cur > 0.001 do scale p [(target/cur),1.0,1.0]
            )
        )
        b.controller.figureMode = false
        sleep 0.3
        L "rig fitted"
        try ( biped.zeroAll b; L "zeroAll(biped) ok" )
        catch ( L ("zeroAll(biped) err " + ((getCurrentException()) as string)) )
        try ( b.controller.zeroAll(); L "zeroAll(ctrl) ok" )
        catch ( L ("zeroAll(ctrl) err " + ((getCurrentException()) as string)) )
        sliderTime = 0f
        local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
        local fs = createFile outPath
        format "bone,x,y,z\n" to:fs
        for o in bones do (
            local q = o.transform.pos
            format "%,%,%,%\n" o.name q.x q.y q.z to:fs
        )
        close fs
        L "rest dumped"
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
