(
    local lg = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText lg "start\n"
    fn L m = ( nf.AppendAllText lg (m + "\n") )
    local FIG = "H:/MyProject/Video2Motion/bvh_out/GVHMR/demo/man_dance_30.fig"
    local BIP = "H:/MyProject/Video2Motion/bvh_out/GVHMR/demo/man_dance_30.bip"
    fn meas tag = (
        at time 0f (
            local lt = getNodeByName "Bip001 L Thigh"
            local lc = getNodeByName "Bip001 L Calf"
            local lf = getNodeByName "Bip001 L Foot"
            local rt = getNodeByName "Bip001 R Thigh"
            local th = distance lt.transform.pos lc.transform.pos
            local cf = distance lc.transform.pos lf.transform.pos
            local hw = distance lt.transform.pos rt.transform.pos
            L (tag + "  thigh=" + (th as string) + "  calf=" + (cf as string) + "  hipw=" + (hw as string) + "  ratio=" + ((hw/th) as string))
        )
    )
    try (
        units.SystemType = #meters
        frameRate = 30
        local b = biped.createNew 1.64 1.0 [0,0,0]
        b.controller.figureMode = false
        sleep 0.4
        meas "1_default_1.64"

        b.controller.figureMode = true
        sleep 0.5
        try ( biped.loadFigFile b.controller FIG; L "   loadFigFile OK" )
            catch ( L ("   loadFigFile ERR: " + ((getCurrentException()) as string)) )
        sleep 0.5
        meas "2_after_loadFig (still figureMode)"
        b.controller.figureMode = false
        sleep 0.5
        meas "3_after_exit_figureMode"

        biped.loadBipFile b.controller BIP
        sleep 0.5
        meas "4_after_loadBip_on_fig"
        L ("anim range " + (animationRange.start as string) + ".." + (animationRange.end as string))
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
