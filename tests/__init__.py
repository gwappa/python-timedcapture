
def profile(device="/dev/video0",
            width=640,
            height=480,
            exposures=[10, 50, 100, 200, 300, 400,
                       500, 600, 700, 800, 900,
                       1000, 1200, 1400, 1600, 1800, 2000,
                       2200, 2400, 2600, 2800, 3000,
                       3200, 3400, 3600, 3800, 4000],
            nframes=500,
            read_unbuffered=False):
    from timedcapture import Device
    from pathlib import Path
    import pandas as pd
    from time import time as now
    import sys
    def log(msg, end="\n"):
        print(msg, end=end, flush=True, file=sys.stderr)

    dev = Device(path=device, width=width, height=height)
    lab = "buffered" if read_unbuffered == False else "unbuffered"
    log(f"---profiling ({nframes} frames, {lab})---")
    data = dict(frame=[], exposure=[], latency=[])
    for exposure in exposures:
        log(f"[INFO] testing: exposure={exposure}...", end="")
        dev.exposure_us = exposure
        dev.start_capture()
        for i in range(1, nframes+1):
            start = now()
            frame = dev.read_frame(read_unbuffered=read_unbuffered)
            end   = now()
            data["frame"].append(i)
            data["exposure"].append(exposure)
            data["latency"].append(end - start)
            for j in range(100):
                pass
        dev.stop_capture()
        log("done.")
    outpath = Path(f"local/latency_{lab}.csv")
    if not outpath.parent.exists():
        outpath.parent.mkdir()
    pd.DataFrame(data).to_csv(str(outpath), index=False)
    log(f"[INFO] output to: {outpath}")
