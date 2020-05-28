#
# MIT License
#
# Copyright (c) 2020 Keisuke Sehara
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

# cython: language_level = 3

import sys
from libc.stdio cimport printf
from libc.string cimport strerror
from libcpp cimport bool as bool_t
from cython.view cimport array as cythonarray
cimport timedcapture.capture as ccapture

DEF EXT_CID_EXPOSURE_TIME_US = 0x0199e201
DEF V4L2_CID_EXPOSURE_AUTO   = 0x009a0901
DEF V4L2_EXPOSURE_MANUAL     = 1

DEF V4L2_CID_GAIN            = 0x00980913
DEF EXT_CID_GAIN_AUTO        = 0x0199e205
DEF EXT_GAIN_MANUAL          = 0

def print_number(int num):
    printf("number: %d\n", num)

cdef cstring_to_str(char* s):
    cdef bytes bs = bytes(s)
    return bs.decode()

cdef format_error_message(ccapture.Device *device):
    cause = cstring_to_str(device.error_cause)
    msg   = cstring_to_str(strerror(device.error_code))
    return f"{cause} (code {device.error_code}, {msg})"

cdef set_control(ccapture.Device* device, ccapture.uint32 cid, ccapture.int32 value):
    if ccapture.capture_set_control(device, cid, value) != 0:
        raise RuntimeError(format_error_message(device))

cdef has_control(ccapture.Device* device, ccapture.uint32 cid):
    cdef bool_t avail
    ccapture.capture_has_control(device, cid, &avail)
    return bool(avail)

cdef set_format(ccapture.Device* device, ccapture.Format* format):
    if ccapture.capture_set_format(device, format) != 0:
        raise RuntimeError(format_error_message(device))

cdef start_capture(ccapture.Device* device, ccapture.uint16[:,:] buffer=None):
    if buffer is None:
        if ccapture.capture_start(device, NULL) != 0:
            raise RuntimeError(format_error_message(device))
    else:
        if ccapture.capture_start(device, &buffer[0,0]) != 0:
            raise RuntimeError(format_error_message(device))

cdef read_frame(ccapture.Device* device, bool_t read_unbuffered=False):
    if ccapture.capture_read(device, read_unbuffered) != 0:
        ccapture.capture_stop(device)
        raise RuntimeError(format_error_message(device))

cdef stop_capture(ccapture.Device* device):
    if ccapture.capture_stop(device) != 0:
        raise RuntimeError(format_error_message(device))

def log(msg, end="\n", file=sys.stderr):
    print(msg, file=file, end=end, flush=True)

def test_calls(path="/dev/video0",
               ccapture.uint16 width=640,
               ccapture.uint16 height=480,
               ccapture.int32 exposure_us=5000,
               ccapture.int32 gain=0):
    """test running a device"""
    import imageio
    from pathlib import Path
    device = ccapture.capture_device_init()
    if device == NULL:
        raise MemoryError()
    format = ccapture.capture_format_init()
    if format == NULL:
        ccapture.capture_device_dealloc(device)
        raise MemoryError()

    # open
    cdef bytes bpath     = path.encode()
    cdef char* path_cstr = <char*>bpath
    if ccapture.capture_open(device, bpath) != 0:
        cause = format_error_message(device)
        ccapture.capture_format_dealloc(format)
        ccapture.capture_device_dealloc(device)
        log(f"***failed to open: {path} ({cause})")
    log(f"[INFO] opened: {path}")

    try:
        # configure width/height
        format.width  = width
        format.height = height
        set_format(device, format)
        log(f"[INFO] width<-{width}, height<-{height}")

        # configure exposure
        if has_control(device, EXT_CID_EXPOSURE_TIME_US) == True:
            set_control(device, V4L2_CID_EXPOSURE_AUTO,   V4L2_EXPOSURE_MANUAL)
            set_control(device, EXT_CID_EXPOSURE_TIME_US, exposure_us)
            log(f"[INFO] exposure_time_us<-{exposure_us}")
        else:
            log(f"***no exposure_time_us setting detected")

        # configure gain
        if has_control(device, EXT_CID_GAIN_AUTO) == True:
            set_control(device, EXT_CID_GAIN_AUTO, EXT_GAIN_MANUAL)
        if has_control(device, V4L2_CID_GAIN) == True:
            set_control(device, V4L2_CID_GAIN, gain)
            log(f"[INFO] gain<-{gain}")
        else:
            log(f"***no gain setting detected")

        # capture
        buf  = cythonarray(shape=(height,width), itemsize=sizeof(ccapture.uint16), format='H') # struct format used
        log("[INFO] capture starting.")
        start_capture(device, buf)
        read_frame(device, True)
        log("[INFO] read 1 frame.")
        outpath = Path("local/frame.png")
        if not outpath.parent.exists():
            outpath.parent.mkdir()
        imageio.imsave(str(outpath), buf)
        log("[INFO] saved the frame.")
        log("[INFO] capture ending.")
        stop_capture(device)
    finally:
        ccapture.capture_close(device)
        ccapture.capture_format_dealloc(format)
        ccapture.capture_device_dealloc(device)
