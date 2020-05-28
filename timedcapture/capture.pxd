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

    Device* capture_device_init()
    void    capture_device_dealloc(Device* device)

    Format* capture_format_init()
    void    capture_format_dealloc(Format* format)

    int     capture_open(Device* device, const char* path)
    int     capture_close(Device* device)

    int     capture_get_format(Device* device, Format* format)
    int     capture_set_format(Device* device, const Format* format)

    uint16  capture_get_input_buffer_num(Device* device)
    int     capture_set_input_buffer_num(Device* device, const uint16 num)

    int     capture_has_control(Device* device,
                                const uint32 cid,
                                bint* out)
    int     capture_get_control(Device* device,
                                const uint32 cid,
                                int32* value)
    int     capture_set_control(Device* device,
                                const uint32 cid,
                                const int32 value)

    int     capture_start(Device *device)
    int     capture_read(Device* device, const bool read_unbuffered=False)
    int     capture_stop(Device* device)
