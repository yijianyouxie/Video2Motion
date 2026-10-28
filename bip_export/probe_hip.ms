(
    local logPath = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local outPath = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/probe_rig.csv"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText logPath "start\n"
    fn L m = ( nf.AppendAllText logPath (m + "\n") )
    local W = "H:/MyProject/Video2Motion/bip_export/_work/"
    local FILES = #(
        #("A_meter_offset335", W + "gvhmr_man_dance_30.bvh"),
        #("B_meter_offset0",   W + "_probe_b_offset0_meter.bvh"),
        #("C_cm_offset0",      W + "_probe_c_offset0_cm.bvh"),
        #("D_cm_offset335",    W + "_probe_d_cm.bvh")
    )
    local fs = createFile outPath
    format "tag,thigh,calf,foot,hipwidth,pelvisZ,headZ,ratio_hip_over_thigh\n" to:fs
    try (
        units.SystemType = #meters
        frameRate = 30
        for it in FILES do (
            local b = biped.createNew 1.64 1.0 [0,0,0]
            b.controller.figureMode = false
            sleep 0.3
            try ( biped.loadMocapFile b.controller it[2] ) catch ( L ("load err " + it[1]) )
            sleep 0.3
            at time 0f (
                local lt = getNodeByName (b.name + " L Thigh")
                local lc = getNodeByName (b.name + " L Calf")
                local lf = getNodeByName (b.name + " L Foot")
                local ltoe = getNodeByName (b.name + " L Toe0")
                local rt = getNodeByName (b.name + " R Thigh")
                local pel = getNodeByName (b.name + " Pelvis")
                local hd = getNodeByName (b.name + " Head")
                local thigh = distance lt.transform.pos lc.transform.pos
                local calf = distance lc.transform.pos lf.transform.pos
                local foot = distance lf.transform.pos ltoe.transform.pos
                local hipw = distance lt.transform.pos rt.transform.pos
                local pelz = pel.transform.pos.z
                local hdz = hd.transform.pos.z
                format "%,%,%,%,%,%,%,%\n" it[1] thigh calf foot hipw pelz hdz (hipw/thigh) to:fs
                L (it[1] + " thigh=" + (thigh as string) + " hipw=" + (hipw as string) + " ratio=" + ((hipw/thigh) as string))
            )
            delete b
            sleep 0.2
        )
        L "done"
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    close fs
    quitMAX #noPrompt
)
