(
    local lg = "H:/MyProject/Video2Motion/bip_export/dump_bip_result.txt"
    local nf = dotNetClass "System.IO.File"
    nf.WriteAllText lg "start\n"
    fn L m = ( nf.AppendAllText lg (m + "\n") )
    try ( L ("mocap props: " + ((getPropNames mocap) as string)) )
        catch ( L ("mocap err: " + ((getCurrentException()) as string)) )
    try (
        L ("kneeOrient now = " + (mocap.kneeOrient as string))
    ) catch ( L ("read kneeOrient err: " + ((getCurrentException()) as string)) )
    try ( mocap.kneeOrient = 0; L ("set kneeOrient=0 -> " + (mocap.kneeOrient as string)) )
        catch ( L ("set kneeOrient err: " + ((getCurrentException()) as string)) )
    quitMAX #noPrompt
)
