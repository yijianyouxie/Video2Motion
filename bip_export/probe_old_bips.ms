(
    local lg = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText lg "start\n"
    fn L m = ( nf.AppendAllText lg (m + "\n") )
    local BASE = "H:/MyProject/Video2Motion/视频转动作小强确认/视频2/"
    local FILES = #(
        #("model1", BASE + "man_dance_30_model1.bip"),
        #("model3", BASE + "man_dance_30_model3.bip"),
        #("model2", BASE + "motion_30_model2.bip")
    )
    try (
        units.SystemType = #meters
        frameRate = 30
        for it in FILES do (
            local b = biped.createNew 1.64 1.0 [0,0,0]
            b.controller.figureMode = false
            sleep 0.4
            local ok = true
            try ( biped.loadBipFile b.controller it[2] )
                catch ( ok = false; L (it[1] + " LOAD ERR " + ((getCurrentException()) as string)) )
            if ok do (
                sleep 0.5
                local bones = for o in objects where ((classOf o as string) == "Biped_Object") collect o
                local sp = for o in bones where (matchPattern o.name pattern:"*Spine*") collect (substituteString o.name "Bip001 " "")
                local lt = getNodeByName "Bip001 L Thigh"
                local lc = getNodeByName "Bip001 L Calf"
                local lf = getNodeByName "Bip001 L Foot"
                local lto = getNodeByName "Bip001 L Toe0"
                local rt = getNodeByName "Bip001 R Thigh"
                local hs = #()
                local toe = #()
                at time 0f (
                    L (it[1] + "  frames=" + (((animationRange.end-animationRange.start)/TicksPerFrame+1) as string) +
                       "  bones=" + (bones.count as string) + "  spine=" + (sp as string)) )
                -- 采样骨盆高度与左脚趾运动量
                local e = animationRange.end
                local pels = #()
                local toes = #()
                for t = animationRange.start to e by (TicksPerFrame*20) do (
                    at time t (
                        append pels (getNodeByName "Bip001 Pelvis").transform.pos.z
                        append toes (distance lto.transform.pos lf.transform.pos) )
                )
                at time 0f (
                    L (it[1] + "  thigh=" + ((distance lt.transform.pos lc.transform.pos) as string) +
                       "  calf=" + ((distance lc.transform.pos lf.transform.pos) as string) +
                       "  foot=" + ((distance lf.transform.pos lto.transform.pos) as string) +
                       "  hipw=" + ((distance lt.transform.pos rt.transform.pos) as string) +
                       "  ratio=" + (((distance lt.transform.pos rt.transform.pos)/(distance lt.transform.pos lc.transform.pos)) as string)) )
                local mn=1e9; local mx=-1e9
                for v in toes do ( if v<mn do mn=v; if v>mx do mx=v )
                local pmn=1e9; local pmx=-1e9
                for v in pels do ( if v<pmn do pmn=v; if v>pmx do pmx=v )
                L (it[1] + "  toeLenRange=" + ((mx-mn) as string) + "  pelvisZ=" + (pmn as string) + ".." + (pmx as string))
                delete b
                sleep 0.3
            )
        )
        L "done"
    ) catch ( L ("ERROR " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
