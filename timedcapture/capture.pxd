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

cimport numpy as np_c

ctypedef np_c.npy_uint16 uint16
ctypedef np_c.npy_uint32 uint32
ctypedef np_c.npy_int32  int32
from libcpp cimport bool as bool_t

cdef extern from "capture.h":

    ctypedef struct Device:
        char*       path
        uint16      input_buffer_num

        int         error_code
        char*       error_cause

    ctypedef struct Format:
        uint16      width
        uint16      height
        char        pixel_format[4]
        # field_type is not exported

    Device* capture_device_init() nogil
    void    capture_device_dealloc(Device* device) nogil

    Format* capture_format_init() nogil
    void    capture_format_dealloc(Format* format) nogil

    int     capture_open(Device* device, const char* path) nogil
    bool_t  capture_is_open(Device* device) nogil
    int     capture_close(Device* device) nogil

    int     capture_get_format(Device* device, Format* format) nogil
    int     capture_set_format(Device* device, const Format* format) nogil

    uint16  capture_get_input_buffer_num(Device* device) nogil
    int     capture_set_input_buffer_num(Device* device, const uint16 num) nogil

    int     capture_has_control(Device* device,
                                const uint32 cid,
                                bint* out) nogil
    int     capture_get_control(Device* device,
                                const uint32 cid,
                                int32* value) nogil
    int     capture_set_control(Device* device,
                                const uint32 cid,
                                const int32 value) nogil
    int     capture_is_triggerable(Device* device, bint* out) nogil
    int     capture_is_triggered(Device* device, bint* triggered) nogil
    int     capture_set_triggered(Device* device, const bint triggered) nogil

    int     capture_has_strobe(Device* device, bint* out) nogil
    int     capture_get_strobe_enabled(Device* device, bint* enabled) nogil
    int     capture_set_strobe_enabled(Device* device, const bint triggered) nogil

    int     capture_start(Device *device, uint16* buffer) nogil
    bool_t  capture_is_running(Device* device) nogil
    int     capture_fire_software_trigger(Device* device) nogil
    int     capture_read(Device* device,
                         const bool_t software_trigger,
                         const bool_t read_unbuffered) nogil
    int     capture_stop(Device* device) nogil
