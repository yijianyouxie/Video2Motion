lg = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/probes/wrap_log.txt"
nfIO = dotNetClass "System.IO.File"
try (
    fileIn "H:/MyProject/Video2Motion/bip_export/probe_max.ms"
    nfIO.WriteAllText lg "fileIn probe_max OK\n"
) catch (
    nfIO.WriteAllText lg ("fileIn ERR: " + ((getCurrentException()) as string) + "\n")
)
quitMAX #noPrompt
