lg = "H:/MyProject/Video2Motion/bvh_out/_bip_dump/probes/m2_log.txt"
nfIO = dotNetClass "System.IO.File"
nfIO.WriteAllText lg "m2 start\n"
fn L m = ( nfIO.AppendAllText lg (m + "\n") )
resetMaxFile #noPrompt
sleep 1
units.SystemType = #meters
frameRate = 30
sleep 2
b = biped.createNew 1.64 1.0 [0,0,0]
spine = getNodeByName (b.name + " Spine")
L ("spine " + (spine as string))
q0 = quat 20.0 [0,0,1]   -- 20 deg about Z (world)
q1 = quat -20.0 [0,0,1]
L ("w0 " + ((spine.transform.rotationpart) as string))

-- T1: biped.setTransform per-bone in ANIMATION mode with at-time
try (
    animate on (
        at time 0f ( biped.setTransform spine #rot q0 true )
        at time 10f ( biped.setTransform spine #rot q1 true )
    )
    at time 0f ( L ("T1 t0 " + ((spine.transform.rotationpart) as string)) )
    at time 5f ( L ("T1 t5 " + ((spine.transform.rotationpart) as string)) )
    at time 10f ( L ("T1 t10 " + ((spine.transform.rotationpart) as string)) )
) catch ( L ("T1 ERR: " + ((getCurrentException()) as string)) )

-- T2: property assignment in animation mode
try (
    spine.rotation = q0
    at time 0f ( L ("T2 t0 " + ((spine.transform.rotationpart) as string)) )
) catch ( L ("T2 ERR: " + ((getCurrentException()) as string)) )

-- T3: figure mode direct rotation
try (
    b.controller.figureMode = true
    spine.rotation = quat 30.0 [1,0,0]
    L ("T3 after fig rot: " + ((getNodeByName (b.name + " Spine1")).transform.pos as string))
    b.controller.figureMode = false
) catch ( L ("T3 ERR: " + ((getCurrentException()) as string)) )

-- T4: biped.setTransform in figure mode
try (
    b.controller.figureMode = true
    biped.setTransform spine #rot (quat 25.0 [1,0,0]) true
    L ("T4 after setT: " + ((getNodeByName (b.name + " Spine1")).transform.pos as string))
    b.controller.figureMode = false
) catch ( L ("T4 ERR: " + ((getCurrentException()) as string)) )

L "m2 done"
quitMAX #noPrompt
