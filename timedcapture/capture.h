#ifndef __capture_h__
/*
 * MIT License
 *
 * Copyright (c) 2020 Keisuke Sehara
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 */
 #include <inttypes.h>
 #include <stdbool.h>
 #include <linux/videodev2.h>

 #define MAX_PATH_LENGTH 256
 #define MAX_CAUSE_LENGTH 256
 #define LENGTH_FOURCC 5

 #define EXT_CID_TRIGGER_MODE     0x0199e208
 #define EXT_CID_SOFTWARE_TRIGGER 0x0199e209
 #define EXT_CID_STROBE_ENABLE    0x0199e211

 // default input buffer size
 #define DEFAULT_BUFFER_NUM 1

 #define Success 0
 #define Failure -1

 typedef enum {
     DeviceIsNotAvailable,
     DeviceIsIdle,
     DeviceIsCapturing
 } DeviceState;

 typedef struct {
     /**
      * current state of this Device.
      */
     DeviceState status;
     bool        triggered;

     /**
      * info of the device associated with this Device.
      */
     char path[MAX_PATH_LENGTH];
     int  fd;

     /**
      * input buffer related parts.
      * allocated and used internally during capture.
      */
     uint16_t   input_buffer_num;
     uint32_t*  input_buffer_size;
     void**     input_buffer;
     void*      input_buffer_info;
     uint16_t   image_width;
     uint16_t   image_height;
     uint16_t*  stored;
     bool       store_extern;

     /**
      * when a function returned Failure(-1), the following values will be filled.
      * you can use `strerror(error_code)`` to retrieve the string repr of the error,
      * in addition to the step where the error occurred as `error_cause`.
      */
     int  error_code;
     char error_cause[MAX_CAUSE_LENGTH];
} Device;

/**
 *  the structure used to configure a Device.
 *  this is a simplified version of `struct v4l2_format`.
 *  although the intent is to remove any library-specific component,
 *  `enum v4l2_field` bleeds out from the V4L2 library for the time being.
 */
typedef struct {
    uint16_t width;
    uint16_t height;
    /**
     *  the FourCC code. defaults to "Y16 "
     */
    char     pixel_format[LENGTH_FOURCC];

    /**
     *  the type that specifies the format of the information transferred at once.
     *  defaults to V4L2_FIELD_NONE (no interlace or whatever, just image as a whole).
     *  this is the only bleeding from V4L2.
     */
    enum v4l2_field field_type;
} Format;

/**
 *  initializes the struct and returns it.
 *  NULL if it fails.
 */
Device* capture_device_init(void);
void    capture_device_dealloc(Device* device);
Format* capture_format_init(void);
void    capture_format_dealloc(Format* format);

/**
 *  associates the Device structure with the device at `path`.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_open(Device* device, const char* path);

bool capture_is_open(Device* device);

/**
 *  closes the device.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_close(Device* device);

/**
 *  reads the current capture configuration, and stores it into `format`.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_get_format(Device* device, Format* format);

/**
 *  sets the capture config of the device.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_set_format(Device* device, const Format* format);

/**
 *  returns the number of input buffer.
 */
uint16_t capture_get_input_buffer_num(Device* device);

/**
 *  sets the number of input buffer.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_set_input_buffer_num(Device* device, const uint16_t num);

/**
 *  queries the device if the control with `cid` is available.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_has_control(Device* device,
                        const uint32_t cid,
                        bool* out);
/**
 *  sets the control with the ID `cid` to the value specified as `value`.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_set_control(Device* device,
                        const uint32_t cid,
                        const int32_t value);

/**
 *  retrieves the value for the control with `cid`.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_get_control(Device* device,
                        const uint32_t cid,
                        int32_t* value);

/**
 *  queries whether the device can be externally triggered.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_is_triggerable(Device* device, bool* out);

/**
 *  retrieves the current trigger mode (false for free-running, true for triggered).
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_is_triggered(Device* device, bool* triggered);

/**
 *  updates the trigger mode to free-running (false) or triggered (true).
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_set_triggered(Device *device, bool triggered);

/**
 *  queries whether the device has STROBE_ENABLE control.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_has_strobe(Device* device, bool* out);

/**
 *  retrieves the current strobe mode (false for disabled, true for enabled).
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_get_strobe_enabled(Device* device, bool* enabled);

/**
 *  updates the strobe mode to enabled (true) or disabled (false).
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_set_strobe_enabled(Device* device, bool enabled);

/**
 *  sets up the input buffer (with the number specified in `input_buffer_num`)
 *  and starts capturing frames.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 *
 *  you can provide the buffer object as the `storage` parameter.
 *  if it is set to NULL, the function prepares the storage by itself.
 */
int capture_start(Device* device, uint16_t* buffer);

bool capture_is_running(Device* device);

/**
 *  fires a software trigger.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_fire_software_trigger(Device* device);

/**
 *  waits until a frame is read and copies it into `stored`.
 *  if `read_unbuffered` is set, it waits until the frame is acquired after this function call.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_read(Device* device, const bool software_trigger, const bool read_unbuffered); // blocks

/**
 *  stops capturing frames, and deallocates buffers.
 *  returns Success (0) on success, and Failure (-1) otherwise.
 */
int capture_stop(Device* device);

#define __capture_h__
#endif
