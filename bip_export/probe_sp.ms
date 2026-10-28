(
    local lg = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText lg "start\n"
    fn L m = ( nf.AppendAllText lg (m + "\n") )
    local BVH = "H:/MyProject/Video2Motion/bip_export/_work/gvhmr_man_dance_30.bvh"
    try (
        units.SystemType = #meters
        frameRate = 30
        local b = biped.createNew 1.64 1.0 [0,0,0]
        b.controller.figureMode = false
        sleep 0.4
        biped.loadMocapFile b.controller BVH
        sleep 0.5
        local lt = getNodeByName "Bip001 L Thigh"
        local lc = getNodeByName "Bip001 L Calf"
        local lf = getNodeByName "Bip001 L Foot"
        local rt = getNodeByName "Bip001 R Thigh"
        at time 0f (
            local th0 = distance lt.transform.pos lc.transform.pos
            local cf0 = distance lc.transform.pos lf.transform.pos
            local hw0 = distance lt.transform.pos rt.transform.pos
            L ("BEFORE spineLinks: thigh=" + (th0 as string) + " calf=" + (cf0 as string) + " hipw=" + (hw0 as string) + " ratio=" + ((hw0/th0) as string))
        )
        b.controller.figureMode = true
        sleep 0.4
        b.controller.spineLinks = 3
        sleep 0.5
        b.controller.figureMode = false
        sleep 0.5
        at time 0f (
            local th1 = distance lt.transform.pos lc.transform.pos
            local cf1 = distance lc.transform.pos lf.transform.pos
            local hw1 = distance lt.transform.pos rt.transform.pos
            L ("AFTER  spineLinks: thigh=" + (th1 as string) + " calf=" + (cf1 as string) + " hipw=" + (hw1 as string) + " ratio=" + ((hw1/th1) as string))
        )
        L "done"
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
