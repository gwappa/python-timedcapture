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

DEBUG = False

DEF EXT_CID_EXPOSURE_TIME_US = 0x0199e201
DEF V4L2_CID_EXPOSURE_AUTO   = 0x009a0901
DEF V4L2_CID_EXPOSURE_ABSOLUTE = 0x009a0902
DEF V4L2_EXPOSURE_MANUAL     = 1
DEF V4L2_EXPOSURE_UNIT       = 10

DEF V4L2_CID_GAIN            = 0x00980913
DEF EXT_CID_GAIN_AUTO        = 0x0199e205
DEF EXT_GAIN_MANUAL          = 0

DEF EXT_CID_STROBE_ENABLE    = 0x0199e211

ctypedef np_c.npy_uint16 uint16
ctypedef np_c.npy_uint32 uint32
ctypedef np_c.npy_int32  int32
ctypedef np_c.npy_int64  int64

cdef extern from "<sys/time.h>":
    struct timeval:
        int64 tv_sec
        int64 tv_usec

    struct timezone:
        pass

    int gettimeofday(timeval *tv, timezone *tz)

def timestamp():
    cdef timeval tv
    cdef timezone* tz = NULL
    gettimeofday(&tv, tz)
    return float(tv.tv_sec) + float(tv.tv_usec)/1000000

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

cdef is_triggered(ccapture.Device* device):
    cdef bool_t status
    if ccapture.capture_is_triggered(device, &status) != 0:
        raise RuntimeError(format_error_message(device))
    return bool(status)

cdef set_triggered(ccapture.Device* device, bool_t triggered):
    if ccapture.capture_set_triggered(device, triggered) != 0:
        raise RuntimeError(format_error_message(device))

cdef set_format(ccapture.Device* device, ccapture.Format* format):
    if ccapture.capture_set_format(device, format) != 0:
        raise RuntimeError(format_error_message(device))

cdef get_strobe_enabled(ccapture.Device* device):
    cdef bool_t status
    if ccapture.capture_get_strobe_enabled(device, &status) != 0:
        raise RuntimeError(format_error_message(device))
    return bool(status)

cdef set_strobe_enabled(ccapture.Device* device, bool_t enabled):
    if ccapture.capture_set_strobe_enabled(device, enabled) != 0:
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

cdef fire_software_trigger(ccapture.Device* device):
    if ccapture.capture_fire_software_trigger(device) != 0:
        raise RuntimeError(format_error_message(device))

cdef read_frame(ccapture.Device* device,
                bool_t software_trigger=True,
                bool_t read_unbuffered=False):
    with nogil:
        if ccapture.capture_read(device, software_trigger, read_unbuffered) != 0:
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
    cdef str              path_str
    cdef uint16[:,:]      buffer
    cdef bool_t           has_exp_us
    cdef bool_t           _device_used

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
        self.path_str = path
        self._device_used = False

        # configure format and buffer
        self.format.width  = width
        self.format.height = height
        try:
            set_format(self.device, self.format)
            set_control(self.device, V4L2_CID_EXPOSURE_AUTO,   V4L2_EXPOSURE_MANUAL)
            if has_control(self.device, EXT_CID_GAIN_AUTO):
                set_control(self.device, EXT_CID_GAIN_AUTO,    EXT_GAIN_MANUAL)
            else:
                import sys
                print(f"***{path}: control 'gain_auto' not found",
                      file=sys.stdout, flush=True)
        except RuntimeError as e:
            ccapture.capture_close(self.device)
            ccapture.capture_device_dealloc(self.device)
            self.device = NULL
            ccapture.capture_format_dealloc(self.format)
            self.format = NULL
            raise e
        self.buffer = cythonarray(shape=(height,width), itemsize=sizeof(uint16), format='H')
        self.has_exp_us = has_control(self.device, EXT_CID_EXPOSURE_TIME_US)
        if self.has_exp_us == False:
            import sys
            print(f"***{path}: control 'exposure_time_us' not found",
                  file=sys.stdout, flush=True)

    def _reopen(self):
        """close the device once, and reopen it."""
        # close device
        if ccapture.capture_is_open(self.device) == True:
            if ccapture.capture_is_running(self.device) == True:
                ccapture.capture_stop(self.device)
            ccapture.capture_close(self.device)
        ccapture.capture_device_dealloc(self.device)
        # open device
        try:
            open_device(self.device, self.path_str)
        except RuntimeError as e:
            ccapture.capture_device_dealloc(self.device)
            self.device = NULL
            ccapture.capture_format_dealloc(self.format)
            self.format = NULL
            raise e

    @property
    def path(self):
        return self.path_str

    @property
    def width(self):
        get_format(self.device, self.format)
        return self.format.width

    @width.setter
    def width(self, uint16 width):
        self.size = (width, self.format.height)

    @property
    def height(self):
        get_format(self.device, self.format)
        return self.format.height

    @height.setter
    def height(self, uint16 height):
        self.size = (self.format.width, height)

    @property
    def size(self):
        get_format(self.device, self.format)
        return (self.format.width, self.format.height)

    @size.setter
    def size(self, (uint16, uint16) width_height):
        # since (at least in the case of ImagingSource cameras)
        # the camera does not accept frame size changes after grab once started,
        # it closes the device once and then re-opens it.
        if self._device_used == True:
            self._reopen()
        self.format.width  = width_height[0]
        self.format.height = width_height[1]
        set_format(self.device, self.format)
        width, height = self.size
        self.buffer = cythonarray(shape=(height,width), itemsize=sizeof(uint16), format='H')

    @property
    def exposure_us(self):
        if self.has_exp_us == True:
            return self.read_control_value(EXT_CID_EXPOSURE_TIME_US, "exposure_us")
        else:
            return self.read_control_value(V4L2_CID_EXPOSURE_ABSOLUTE, "exposure_absolute")*V4L2_EXPOSURE_UNIT

    @exposure_us.setter
    def exposure_us(self, int32 exposure_us):
        if self.has_exp_us == True:
            self.write_control_value(EXT_CID_EXPOSURE_TIME_US, exposure_us, "exposure_us")
        else:
            self.write_control_value(V4L2_CID_EXPOSURE_ABSOLUTE, exposure_us // 10, "exposure_absolute")

    @property
    def gain(self):
        return self.read_control_value(V4L2_CID_GAIN, "gain")

    @gain.setter
    def gain(self, int32 gain):
        self.write_control_value(V4L2_CID_GAIN, gain, "gain")

    @property
    def nb_buffer(self):
        """number of input buffer on the driver"""
        return self.device.input_buffer_num

    @nb_buffer.setter
    def nb_buffer(self, uint16 value):
        self.device.input_buffer_num = value

    @property
    def triggered(self):
        return is_triggered(self.device)

    @triggered.setter
    def triggered(self, bool_t triggered):
        set_triggered(self.device, triggered)

    @property
    def strobe(self):
        if has_control(self.device, EXT_CID_STROBE_ENABLE) == True:
            return get_strobe_enabled(self.device)
        else:
            return None

    @strobe.setter
    def strobe(self, bool_t enabled):
        if has_control(self.device, EXT_CID_STROBE_ENABLE) == True:
            set_strobe_enabled(self.device, enabled)
        else:
            pass

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
        self._device_used = True

    def fire_software_trigger(self):
        fire_software_trigger(self.device)

    def read_frame(self,
                   bool_t software_trigger=True,
                   bool_t read_unbuffered=False,
                   bool_t copy=False):
        read_frame(self.device, software_trigger, read_unbuffered)
        return np.array(self.buffer, copy=copy)

    def stop_capture(self):
        stop_capture(self.device)

    def close(self):
        if self.device is not NULL:
            if ccapture.capture_is_open(self.device) == True:
                if ccapture.capture_is_running(self.device) == True:
                    ccapture.capture_stop(self.device)
                ccapture.capture_close(self.device)
            ccapture.capture_device_dealloc(self.device)
        if self.format is not NULL:
            ccapture.capture_format_dealloc(self.format)

    def __dealloc__(self):
        self.close()

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
