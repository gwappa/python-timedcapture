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
from libc.string cimport strerror
from libcpp cimport bool as bool_t
from cython.view cimport array as cythonarray
import numpy as np
cimport numpy as np_c
cimport timedcapture.capture as ccapture

DEBUG = True

DEF EXT_CID_EXPOSURE_TIME_US = 0x0199e201
DEF V4L2_CID_EXPOSURE_AUTO   = 0x009a0901
DEF V4L2_EXPOSURE_MANUAL     = 1

DEF V4L2_CID_GAIN            = 0x00980913
DEF EXT_CID_GAIN_AUTO        = 0x0199e205
DEF EXT_GAIN_MANUAL          = 0

ctypedef np_c.npy_uint16 uint16
ctypedef np_c.npy_uint32 uint32
ctypedef np_c.npy_int32  int32

cdef cstring_to_str(char* s):
    cdef bytes bs = bytes(s)
    return bs.decode()

cdef format_error_message(ccapture.Device *device):
    cause = cstring_to_str(device.error_cause)
    msg   = cstring_to_str(strerror(device.error_code))
    return f"{cause} (code {device.error_code}, {msg})"

cdef open_device(ccapture.Device* device, str path):
    cdef bytes bpath     = path.encode()
    cdef char* path_cstr = <char*>bpath
    if ccapture.capture_open(device, path_cstr) != 0:
        raise RuntimeError(format_error_message(device))

cdef set_control(ccapture.Device* device, uint32 cid, int32 value):
    if ccapture.capture_set_control(device, cid, value) != 0:
        raise RuntimeError(format_error_message(device))

cdef int32 get_control(ccapture.Device* device, uint32 cid):
    cdef int32 value
    if ccapture.capture_get_control(device, cid, &value) != 0:
        raise RuntimeError(format_error_message(device))
    return value

cdef has_control(ccapture.Device* device, uint32 cid):
    cdef bool_t avail
    ccapture.capture_has_control(device, cid, &avail)
    return bool(avail)

cdef set_format(ccapture.Device* device, ccapture.Format* format):
    if ccapture.capture_set_format(device, format) != 0:
        raise RuntimeError(format_error_message(device))

cdef get_format(ccapture.Device* device, ccapture.Format* format):
    if ccapture.capture_get_format(device, format) != 0:
        raise RuntimeError(format_error_message(device))

cdef start_capture(ccapture.Device* device, uint16[:,:] buffer=None):
    if buffer is None:
        if ccapture.capture_start(device, NULL) != 0:
            raise RuntimeError(format_error_message(device))
    else:
        if ccapture.capture_start(device, &buffer[0,0]) != 0:
            raise RuntimeError(format_error_message(device))

cdef read_frame(ccapture.Device* device, bool_t read_unbuffered=False):
    with nogil:
        if ccapture.capture_read(device, read_unbuffered) != 0:
            ccapture.capture_stop(device)
            with gil:
                raise RuntimeError(format_error_message(device))

cdef stop_capture(ccapture.Device* device):
    if ccapture.capture_stop(device) != 0:
        raise RuntimeError(format_error_message(device))

def log(msg, end="\n", file=sys.stderr):
    if DEBUG == True:
        print(msg, file=file, end=end, flush=True)

cdef class Device:
    cdef ccapture.Device* device
    cdef ccapture.Format* format
    cdef str              path
    cdef uint16[:,:]      buffer

    def __cinit__(self,
                  str path="/dev/video0",
                  uint16 width=640,
                  uint16 height=480):
        # prepare device/format
        self.device = ccapture.capture_device_init()
        if self.device == NULL:
            raise MemoryError()
        self.format = ccapture.capture_format_init()
        if self.format == NULL:
            ccapture.capture_device_dealloc(self.device)
            self.device = NULL
            raise MemoryError()

        # open device
        try:
            open_device(self.device, path)
        except RuntimeError as e:
            ccapture.capture_device_dealloc(self.device)
            self.device = NULL
            ccapture.capture_format_dealloc(self.format)
            self.format = NULL
            raise e
        self.path = path

        # configure format and buffer
        self.format.width  = width
        self.format.height = height
        try:
            set_format(self.device, self.format)
            set_control(self.device, V4L2_CID_EXPOSURE_AUTO,   V4L2_EXPOSURE_MANUAL)
            set_control(self.device, EXT_CID_GAIN_AUTO,        EXT_GAIN_MANUAL)
        except RuntimeError as e:
            ccapture.capture_close(self.device)
            ccapture.capture_device_dealloc(self.device)
            self.device = NULL
            ccapture.capture_format_dealloc(self.format)
            self.format = NULL
            raise e
        self.buffer = cythonarray(shape=(height,width), itemsize=sizeof(uint16), format='H')

    @property
    def width(self):
        get_format(self.device, self.format)
        return self.format.width

    @width.setter
    def width(self, uint16 width):
        self.format.width = width
        set_format(self.device, self.format)

    @property
    def height(self):
        get_format(self.device, self.format)
        return self.format.height

    @height.setter
    def height(self, uint16 height):
        self.format.height = height
        set_format(self.device, self.format)

    @property
    def size(self):
        get_format(self.device, self.format)
        return (self.format.width, self.format.height)

    @size.setter
    def size(self, (uint16, uint16) width_height):
        self.format.width  = width_height[0]
        self.format.height = width_height[1]
        set_format(self.device, self.format)

    @property
    def exposure_us(self):
        return self.read_control_value(EXT_CID_EXPOSURE_TIME_US, "exposure_us")

    @exposure_us.setter
    def exposure_us(self, int32 exposure_us):
        self.write_control_value(EXT_CID_EXPOSURE_TIME_US, exposure_us, "exposure_us")

    @property
    def gain(self):
        return self.read_control_value(V4L2_CID_GAIN, "gain")

    @gain.setter
    def gain(self, int32 gain):
        self.write_control_value(V4L2_CID_GAIN, gain, "gain")

    cdef int32 read_control_value(self, uint32 cid, str label):
        if has_control(self.device, cid) == True:
            return get_control(self.device, cid)
        else:
            raise AttributeError(f"device does not have control: {label}")

    cdef write_control_value(self, uint32 cid, int32 value, str label):
        if has_control(self.device, cid) == True:
            set_control(self.device, cid, value)
        else:
            raise AttributeError(f"cannot control: {label}")

    def start_capture(self):
        start_capture(self.device, self.buffer)

    def read_frame(self, bool_t read_unbuffered=False, bool_t copy=False):
        read_frame(self.device, read_unbuffered)
        return np.array(self.buffer, copy=copy)

    def stop_capture(self):
        stop_capture(self.device)

    def __dealloc__(self):
        if self.device is not NULL:
            if ccapture.capture_is_open(self.device) == True:
                if ccapture.capture_is_running(self.device) == True:
                    ccapture.capture_stop(self.device)
                ccapture.capture_close(self.device)
            ccapture.capture_device_dealloc(self.device)
        if self.format is not NULL:
            ccapture.capture_format_dealloc(self.format)

def test_calls(path="/dev/video0",
               uint16 width=640,
               uint16 height=480,
               int32 exposure_us=5000,
               int32 gain=0):
    """test running a device"""
    import imageio
    from pathlib import Path
    log("---test_calls---")
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
        buf  = cythonarray(shape=(height,width), itemsize=sizeof(uint16), format='H') # struct format used
        log("[INFO] capture starting.")
        start_capture(device, buf)
        read_frame(device, True)
        log("[INFO] read 1 frame.")
        outpath = Path("local/frame_func.png")
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

def test_device(path="/dev/video0",
               uint16 width=640,
               uint16 height=480,
               int32 exposure_us=5000,
               int32 gain=0):
    import imageio
    from pathlib import Path
    log("---test_device---")
    log(f"[INFO] initializing a device: {path}")
    device = Device(path)
    log("[INFO] setting parameters")
    device.width = width
    device.height = height
    device.size = (width, height)
    device.exposure_us = exposure_us
    device.gain = gain
    log(f"[INFO] width={device.width}, height={device.height}, exposure_us={device.exposure_us}, gain={device.gain}")
    log("[INFO] capture starting.")
    device.start_capture()
    log("[INFO] reading and saving 1 frame.")
    outpath = Path("local/frame_obj.png")
    if not outpath.parent.exists():
        outpath.parent.mkdir()
    imageio.imsave(str(outpath), device.read_frame(True))
    log("[INFO] capture ending.")
    device.stop_capture()