(
    local logPath = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local outPath = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/probe_rig2.csv"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText logPath "start\n"
    fn L m = ( nf.AppendAllText logPath (m + "\n") )
    local BVH = "H:/MyProject/Video2Motion/bip_export/_work/gvhmr_man_dance_30.bvh"

    local FIT = #(
        #(" Pelvis"," Spine",0.107956), #(" Spine"," Spine1",0.127912),
        #(" Spine1"," Spine2",0.054600), #(" Spine2"," Spine3",0.003000),
        #(" Spine3"," Neck",0.163354),  #(" Neck"," Head",0.166197),
        #(" L Clavicle"," L UpperArm",0.123058), #(" L UpperArm"," L Forearm",0.272029),
        #(" L Forearm"," L Hand",0.257537),
        #(" R Clavicle"," R UpperArm",0.107930), #(" R UpperArm"," R Forearm",0.279066),
        #(" R Forearm"," R Hand",0.254314),
        #(" L Thigh"," L Calf",0.405915), #(" L Calf"," L Foot",0.425126), #(" L Foot"," L Toe0",0.139714),
        #(" R Thigh"," R Calf",0.389207), #(" R Calf"," R Foot",0.431272), #(" R Foot"," R Toe0",0.138251)
    )

    fn doFit b = (
        b.controller.figureMode = true
        sleep 0.3
        for it in FIT do (
            local p = getNodeByName (b.name + it[1])
            local c = getNodeByName (b.name + it[2])
            if p != undefined and c != undefined do (
                local cur = distance p.transform.pos c.transform.pos
                if cur > 0.001 do scale p [(it[3]/cur), 1.0, 1.0] ) )
        b.controller.figureMode = false
        sleep 0.3
    )

    fn measure tag b = (
        at time 0f (
            local lt = getNodeByName (b.name + " L Thigh")
            local lc = getNodeByName (b.name + " L Calf")
            local rt = getNodeByName (b.name + " R Thigh")
            local thigh = distance lt.transform.pos lc.transform.pos
            local hipw = distance lt.transform.pos rt.transform.pos
            local r = hipw/thigh
            L (tag + "  thigh=" + (thigh as string) + "  hipw=" + (hipw as string) + "  ratio=" + (r as string))
            " ," + tag + "," + (thigh as string) + "," + (hipw as string) + "," + (r as string) + "\n"
        )
    )

    local fs = createFile outPath
    format "tag,thigh,hipw,ratio\n" to:fs
    try (
        units.SystemType = #meters
        frameRate = 30
        L "source: thigh=0.405915 hipw=0.113752 ratio=0.280236"

        local bH = biped.createNew 1.64 1.0 [0,0,0]
        bH.controller.figureMode = false
        sleep 0.3
        biped.loadMocapFile bH.controller BVH
        sleep 0.4
        format "%" (measure "H_baseline" bH) to:fs
        delete bH

        local bE = biped.createNew 1.64 1.0 [0,0,0]
        bE.controller.figureMode = false
        sleep 0.3
        biped.loadMocapFile bE.controller BVH
        sleep 0.4
        bE.controller.figureMode = true
        sleep 0.4
        bE.controller.spineLinks = 3
        sleep 0.4
        bE.controller.figureMode = false
        sleep 0.4
        format "%" (measure "E_spineLinks3" bE) to:fs
        delete bE

        local bF = biped.createNew 1.64 1.0 [0,0,0]
        bF.controller.figureMode = false
        sleep 0.3
        biped.loadMocapFile bF.controller BVH
        sleep 0.4
        doFit bF
        format "%" (measure "F_fitOnly" bF) to:fs
        delete bF

        local bG = biped.createNew 1.64 1.0 [0,0,0]
        bG.controller.figureMode = false
        sleep 0.3
        biped.loadMocapFile bG.controller BVH
        sleep 0.4
        bG.controller.figureMode = true
        sleep 0.4
        bG.controller.spineLinks = 3
        sleep 0.4
        bG.controller.figureMode = false
        sleep 0.3
        doFit bG
        format "%" (measure "G_spineLinks3_fit" bG) to:fs
        delete bG

        L "done"
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    close fs
    quitMAX #noPrompt
)
