import timedcapture as tcap
from . import profile

run_profile_buffered = True
run_profile_unbuffered = True

print("[INFO] testing timedcapture.", flush=True)
tcap.test_calls()
tcap.test_device()
if run_profile_buffered == True:
    profile(read_unbuffered=False)
else:
    print("[INFO] (omitted profiling buffered reads)")
if run_profile_unbuffered == True:
    profile(read_unbuffered=True)
else:
    print("[INFO] (omitted profiling unbuffered reads)")
