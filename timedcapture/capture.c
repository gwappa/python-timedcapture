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

/**
 *  referred to:
 *  - https://qiita.com/iwatake2222/items/d6645880c5bb91ce8a85
 *  - https://qiita.com/ykatsu111/items/9ba57e9bb6c36f434526
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h> // close
#include <sys/fcntl.h> // open
#include <sys/ioctl.h> // ioctl
#include <sys/mman.h> // mmap, munmap etc
#include <linux/videodev2.h>

#include "capture.h"

#define DEVICE_FLAG (O_RDWR | O_NONBLOCK)
//#define DEBUG

static void read_pixel_format(uint32_t value, char* out)
{
    out[3] = (char)((value >> 24) & (uint32_t)0xFF);
    out[2] = (char)((value >> 16) & (uint32_t)0xFF);
    out[1] = (char)((value >> 8) & (uint32_t)0xFF);
    out[0] = (char)((value) & (uint32_t)0xFF);
    out[4] = '\0';
}

#define as_pixel_format(repr) v4l2_fourcc((repr)[0], (repr)[1], (repr)[2], (repr)[3])

static void free_input_buffers(Device* device, const size_t size)
{
    for (uint16_t j=0; j<size; j++){
#ifdef DEBUG
    fprintf(stderr, "[DEBUG] buffer #%u: freeing...", j);
#endif
        // TODO: should we dequeue the buffer explicitly for cleanup??
        munmap(*(device->input_buffer + j), *(device->input_buffer_size + j));
#ifdef DEBUG
    fprintf(stderr, "done.\n");
#endif
    }
#ifdef DEBUG
    fprintf(stderr, "[DEBUG] cleaning up...");
#endif
    free(device->input_buffer);
    free(device->input_buffer_size);
    free(device->input_buffer_info);
    if (!device->store_extern)
        free(device->stored);
    device->store_extern = false;
#ifdef DEBUG
    fprintf(stderr, "done.\n");
#endif
}

Device* capture_device_init()
{
    Device* dev = (Device*)malloc(sizeof(Device));
    if (!dev) {
        return NULL;
    }
    memset(dev, 0, sizeof(Device));
    dev->triggered        = false;
    dev->input_buffer_num = DEFAULT_BUFFER_NUM;
    dev->fd = -1;
    dev->status = DeviceIsNotAvailable;
    dev->store_extern = false;
    return dev;
}

void capture_device_dealloc(Device* device)
{
    switch(device->status)
    {
        case DeviceIsCapturing:
            if (Success != capture_stop(device)){
                fprintf(stderr, "***capture: failed to stop capturing: %s (code %d, %s)\n",
                        device->error_cause,
                        device->error_code,
                        strerror(device->error_code));
            }
        case DeviceIsIdle:
            if (Success != capture_close(device)){
                fprintf(stderr, "***capture: failed to close device: %s (code %d, %s)\n",
                        device->error_cause,
                        device->error_code,
                        strerror(device->error_code));
            }
        case DeviceIsNotAvailable:
            break;
    }
    free(device);
}

Format* capture_format_init()
{
    Format* format = (Format*) malloc(sizeof(Format));
    if (!format) {
        return NULL;
    }
    memset(format, 0, sizeof(Format));
    strcpy(format->pixel_format, "Y16 ");
    format->field_type = V4L2_FIELD_NONE;
    return format;
}

void capture_format_dealloc(Format* format)
{
    free(format);
}

int capture_open(Device* device, const char* path)
{
    int fd;
    struct v4l2_capability cap;

    // initialize with name
    strncpy(device->path, path, MAX_PATH_LENGTH);
    device->path[MAX_PATH_LENGTH-1] = '\0';

    // open
    fd = open(device->path, DEVICE_FLAG, 0);
    if (-1 == fd) {
        device->error_code  = errno;
        device->status      = DeviceIsNotAvailable;
        strcpy(device->error_cause, "open");
        return Failure;
    }
#ifdef DEBUG
    fprintf(stderr, "[DEBUG] opened device: %s\n", device->path);
#endif

    device->fd     = fd;
    device->error_code = 0;
    device->status     = DeviceIsIdle;
    memset(device->error_cause, 0, MAX_CAUSE_LENGTH);

    // validate device type
    if (-1 == ioctl(fd, VIDIOC_QUERYCAP, &cap))
    {
        int cap_error = errno;
        // close device first, otherwise the message will be overridden.
        capture_close(device);
        device->error_code = cap_error;

        if (EINVAL == cap_error)
        {
            strcpy(device->error_cause, "invalid device to be controlled from V4L2");
            return Failure;
        }
        else {
            strcpy(device->error_cause, "VIDIOC_QUERYCAP (querying device capability)");
        }
    }
    if (!(cap.capabilities & V4L2_CAP_VIDEO_CAPTURE))
    {
        capture_close(device);
        strcpy(device->error_cause, "device does not have video-capture capability");
        device->error_code = EINVAL;
        return Failure;
    }

#ifdef DEBUG
    fprintf(stderr, "[DEBUG] successfully validated device capability.\n");
#endif

    return Success;
}

bool capture_is_open(Device* device)
{
    return (device->status != DeviceIsNotAvailable);
}

int capture_close(Device* device)
{
    switch(device->status)
    {
        case DeviceIsNotAvailable:
            // no need to do anything;
            return Success;
        case DeviceIsIdle:
            break;
        case DeviceIsCapturing:
            capture_stop(device);
            // force closing anyway, discarding any possible errors
            break;
    }

    if (-1 == close(device->fd)) {
        device->error_code = errno;
        device->status     = DeviceIsNotAvailable;
        strcpy(device->error_cause, "close");
        return Failure;
    }

#ifdef DEBUG
    fprintf(stderr, "[DEBUG] closed device: %s\n", device->path);
#endif
    device->fd     = -1;
    device->status = DeviceIsNotAvailable;
    return Success;
}

int capture_get_format(Device* device, Format* format)
{
    struct v4l2_format fmt;

    fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (-1 == ioctl(device->fd, VIDIOC_G_FMT, &fmt))
    {
        device->error_code = errno;
        strcpy(device->error_cause, "VIDIOC_G_FMT (querying image format)");
        return Failure;
    }
    format->width  = fmt.fmt.pix.width;
    format->height = fmt.fmt.pix.height;
    read_pixel_format(fmt.fmt.pix.pixelformat, format->pixel_format);

    /*
    char repr[64];
    strcpy(repr, "(UNKNOWN)");
    switch(fmt.fmt.pix.field)
    {
    #define add_case(S) case V4L2_FIELD_##S: strcpy(repr, #S ); break
        add_case(ANY);
        add_case(NONE);
        add_case(TOP);
        add_case(BOTTOM);
        add_case(INTERLACED);
        add_case(SEQ_TB);
        add_case(SEQ_BT);
        add_case(ALTERNATE);
        add_case(INTERLACED_TB);
        add_case(INTERLACED_BT);
    #undef add_case
    }
    fprintf(stderr, "[INFO]   field order: '%s'\n", repr);
    fprintf(stderr, "[INFO]   bytes per line: %u\n", fmt.fmt.pix.bytesperline);
    fprintf(stderr, "[INFO]   buffer size per frame: %u\n", fmt.fmt.pix.sizeimage);
    */
    return Success;
}

int capture_set_format(Device* device, const Format* format)
{
    switch(device->status)
    {
        case DeviceIsNotAvailable:
            device->error_code = EINVAL;
            strcpy(device->error_cause, "device closed or not available");
            return Failure;
        case DeviceIsIdle:
            break;
        case DeviceIsCapturing:
            device->error_code = EINVAL;
            strcpy(device->error_cause, "cannot set format during capture");
            return Failure;
    }
    struct v4l2_format  fmt;

    // configure width/heigh and the format
    memset(&fmt, 0, sizeof(fmt));
    fmt.type                = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    fmt.fmt.pix.width       = format->width;
    fmt.fmt.pix.height      = format->height;
    fmt.fmt.pix.pixelformat = as_pixel_format(format->pixel_format);
    fmt.fmt.pix.field       = format->field_type;

    if (ioctl(device->fd, VIDIOC_S_FMT, &fmt))
    {
        device->error_code = errno;
        strcpy(device->error_cause, "VIDIOC_S_FMT (pixel format configuration)");
        return Failure;
    }

    return Success;
}

uint16_t capture_get_input_buffer_num(Device* device)
{
    return device->input_buffer_num;
}

int capture_set_input_buffer_num(Device* device, const uint16_t num)
{
    switch(device->status)
    {
        case DeviceIsNotAvailable:
            device->error_code = EINVAL;
            strcpy(device->error_cause, "device closed or not available");
            return Failure;
        case DeviceIsIdle:
            break;
        case DeviceIsCapturing:
            device->error_code = EINVAL;
            strcpy(device->error_cause, "cannot set format during capture");
            return Failure;
    }
    device->input_buffer_num = num;
    return Success;
}

int capture_has_control(Device* device,
                        const uint32_t cid,
                        bool* out)
{
    struct v4l2_queryctrl qctrl;
    qctrl.id = cid;

    if (ioctl(device->fd, VIDIOC_QUERYCTRL, &qctrl))
    {
        device->error_code = errno;
        if (errno != EINVAL) {
            snprintf(device->error_cause, MAX_CAUSE_LENGTH,
                     "VIDIOC_QUERYCTRL failed (CID: %x)", cid);
            *out = false;
            return Failure;
        } else {
            snprintf(device->error_cause, MAX_CAUSE_LENGTH,
                    "device does not support the control (CID: %x)", cid);
            *out = false;
            return Success;
        }
    }


    if (qctrl.flags & V4L2_CTRL_FLAG_DISABLED)
    {
        device->error_code = EINVAL;
        snprintf(device->error_cause, MAX_CAUSE_LENGTH,
                "the control is disabled on device (CID: %x)", cid);
        *out = false;
        return Success;
    }
    *out = true;
    return Success;
}

int capture_get_control(Device* device,
                        const uint32_t cid,
                        int32_t* value)
{
    bool available;
    if ( (Failure == capture_has_control(device, cid, &available)) ||
            (!available) )
    {
        return Failure;
    }

    // query the value
    struct v4l2_control ctrl;
    memset(&ctrl, 0, sizeof(ctrl));
    ctrl.id    = cid;
    if (ioctl(device->fd, VIDIOC_G_CTRL, &ctrl))
    {
        device->error_code = errno;
        snprintf(device->error_cause,
                 MAX_CAUSE_LENGTH,
                 "VIDIOC_G_CTRL (retrieval of current control) failed (CID: %x)",
                 cid);
        return Failure;
    }
    *value = ctrl.value;
    return Success;
}

int capture_set_control(Device* device,
                        const uint32_t cid,
                        const int32_t value)
{
    switch(device->status)
    {
        case DeviceIsNotAvailable:
            device->error_code = EINVAL;
            strcpy(device->error_cause, "device closed or not available");
            return Failure;
        case DeviceIsIdle:
            break;
        case DeviceIsCapturing:
            break;
    }

    bool available;
    if ( (Failure == capture_has_control(device, cid, &available)) ||
            (!available) )
    {
        return Failure;
    }
#ifdef DEBUG
    fprintf(stderr, "[DEBUG] SET: %x <- %d\n", cid, value);
#endif

    // configure
    struct v4l2_control ctrl;
    memset(&ctrl, 0, sizeof(ctrl));
    ctrl.id    = cid;
    ctrl.value = value;
    if (ioctl(device->fd, VIDIOC_S_CTRL, &ctrl))
    {
        device->error_code = errno;
        snprintf(device->error_cause,
                 MAX_CAUSE_LENGTH,
                 "VIDIOC_S_CTRL (updating a control) failed (CID: %x)",
                 cid);
        return Failure;
    }
    return Success;
}

int capture_is_triggerable(Device* device, bool* out)
{
    return capture_has_control(device, EXT_CID_TRIGGER_MODE, out);
}

int capture_is_triggered(Device* device, bool* triggered)
{
    int status = 0;
    int ret    = capture_get_control(device, EXT_CID_TRIGGER_MODE, &status);
    *triggered = status? true: false;
    device->triggered = *triggered;
    return ret;
}

int capture_set_triggered(Device* device, bool triggered)
{
    int ret = capture_set_control( device, EXT_CID_TRIGGER_MODE, (triggered? 1 : 0) );
    if (ret == Success) {
        device->triggered = triggered;
    }
    return ret;
}

int capture_has_strobe(Device* device, bool* out)
{
    return capture_has_control(device, EXT_CID_STROBE_ENABLE, out);
}

int capture_get_strobe_enabled(Device* device, bool* enabled)
{
    int status = 0;
    int ret    = capture_get_control(device, EXT_CID_STROBE_ENABLE, &status);
    *enabled   = status? true: false;
    return ret;
}

int capture_set_strobe_enabled(Device* device, bool enabled)
{
    return capture_set_control(device, EXT_CID_STROBE_ENABLE, (enabled? 1:0));
}

int capture_start(Device* device, uint16_t* buffer)
{
    switch(device->status)
    {
        case DeviceIsNotAvailable:
            device->error_code = EINVAL;
            strcpy(device->error_cause, "device closed or not available");
            return Failure;
        case DeviceIsIdle:
            break;
        case DeviceIsCapturing:
            device->error_code = EINVAL;
            strcpy(device->error_cause, "already running a capture");
            return Failure;
    }

    // 1/5. query current format
    struct v4l2_format fmt;
    memset(&fmt, 0, sizeof(fmt));
    fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (ioctl(device->fd, VIDIOC_G_FMT, &fmt))
    {
        device->error_code = errno;
        strcpy(device->error_cause, "VIDIOC_G_FMT (querying image format)");
        return Failure;
    }
    device->image_width  = fmt.fmt.pix.width;
    device->image_height = fmt.fmt.pix.height;

    // 2/5. prepare input buffer
    struct v4l2_requestbuffers req;
    memset(&req, 0, sizeof(req));
    req.count  = device->input_buffer_num;
    req.type   = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    req.memory = V4L2_MEMORY_MMAP;
    if (ioctl(device->fd, VIDIOC_REQBUFS, &req))
    {
        device->error_code = errno;
        strcpy(device->error_cause, "cannot allocate driver-side buffer");
        return Failure;
    }

    if (buffer == NULL) {
#ifdef DEBUG
        fprintf(stderr, "[DEBUG] prepare internal-storage buffer (%dx%d)...",
                device->image_width, device->image_height);
#endif
        device->stored       = (uint16_t *)malloc(sizeof(uint16_t)
                                                  * (device->image_width)
                                                  * (device->image_height));
        device->store_extern = false;
#ifdef DEBUG
        fprintf(stderr, "done.\n");
#endif
    } else {
#ifdef DEBUG
        fprintf(stderr, "[DEBUG] set up externally-prepared buffer as the storage (%dx%d).\n",
                device->image_width, device->image_height);
#endif
        device->stored       = buffer;
        device->store_extern = true;
    }

#ifdef DEBUG
    fprintf(stderr, "[DEBUG] setting up %d buffers of %dx%d:\n",
            device->input_buffer_num, device->image_width, device->image_height);
#endif

    // 3/5. prepare buffer address storage
    device->input_buffer      = (void **)malloc(sizeof(void *) * device->input_buffer_num);
    device->input_buffer_size = (uint32_t *)malloc(sizeof(uint32_t) * device->input_buffer_num);
    device->input_buffer_info = malloc(sizeof(struct v4l2_buffer));

    // 4/5. mmap buffer info
    struct v4l2_buffer* buf = (struct v4l2_buffer*)device->input_buffer_info;
    for (uint16_t i=0; i<device->input_buffer_num; i++)
    {
        memset(device->input_buffer + i, 0, sizeof(void *));
        memset(device->input_buffer_size + i, 0, sizeof(uint32_t));
        memset(buf, 0, sizeof(struct v4l2_buffer));
        buf->type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf->memory = V4L2_MEMORY_MMAP;
        buf->index  = i;
#ifdef DEBUG
        fprintf(stderr, "[DEBUG] buffer #%u: preparing...", i);
#endif

        // query buffer address
        if (ioctl(device->fd, VIDIOC_QUERYBUF, buf))
        {
            device->error_code = errno;
            strcpy(device->error_cause, "failed to obtain info about driver-side buffer");
            free_input_buffers(device, i);
            return Failure;
        }

        // map onto the process's address space
        *(device->input_buffer + i) = mmap(NULL,
                                            buf->length,
                                            PROT_READ,
                                            MAP_SHARED,
                                            device->fd,
                                            buf->m.offset);
        *(device->input_buffer_size + i) = buf->length;

        if (i < device->input_buffer_num - 1) {
            // enqueue the buffer, except for the last one
#ifdef DEBUG
            fprintf(stderr, "enqueing...");
#endif
            memset(buf, 0, sizeof(struct v4l2_buffer));
            buf->type   = V4L2_BUF_TYPE_VIDEO_CAPTURE;
            buf->memory = V4L2_MEMORY_MMAP;
            buf->index  = i;
            if (ioctl(device->fd, VIDIOC_QBUF, buf))
            {
                device->error_code = errno;
                strcpy(device->error_cause, "failed to queue input buffer");
                free_input_buffers(device, i);
                return Failure;
            }
        } else {
            device->input_buffer_info = buf;
        }

#ifdef DEBUG
        fprintf(stderr, "done.\n");
#endif
    }
#ifdef DEBUG
    fprintf(stderr, "[DEBUG] successfully set up capturing.\n");
#endif

    // 5/5. start capturing
#ifdef DEBUG
    fprintf(stderr, "[DEBUG] starting capture...");
#endif

    enum v4l2_buf_type type;
    type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (ioctl(device->fd, VIDIOC_STREAMON, &type))
    {
        device->error_code = errno;
        strcpy(device->error_cause, "device failed to start capture");
        free_input_buffers(device, device->input_buffer_num);
        return Failure;
    }

#ifdef DEBUG
    fprintf(stderr, "success\n");
#endif
    device->status = DeviceIsCapturing;
    return Success;
}

bool capture_is_running(Device* device)
{
    return (device->status == DeviceIsCapturing);
}

int capture_fire_software_trigger(Device* device)
{
    // generate software trigger
    // note, in this condition, the device must respond to EXT_CID_SOFTWARE_TRIGGER

    struct v4l2_control trig;
    memset(&trig, 0, sizeof(trig));
    trig.id    = EXT_CID_SOFTWARE_TRIGGER;
    trig.value = 1; // but can be anything
    if (ioctl(device->fd, VIDIOC_S_CTRL, &trig))
    {
        device->error_code = errno;
        snprintf(device->error_cause,
                 MAX_CAUSE_LENGTH,
                 "failed to generate a software trigger (CID: %x)",
                 EXT_CID_SOFTWARE_TRIGGER);
        return Failure;
    }
    return Success;
}

int capture_read(Device* device, const bool software_trigger, const bool read_unbuffered)
{
    switch(device->status)
    {
        case DeviceIsNotAvailable:
            device->error_code = EINVAL;
            strcpy(device->error_cause, "device closed or not available");
            return Failure;
        case DeviceIsIdle:
            device->error_code = EINVAL;
            strcpy(device->error_cause, "device is not capturing frames");
            return Failure;
        case DeviceIsCapturing:
            break;
    }

    struct v4l2_buffer* buf = (struct v4l2_buffer*)device->input_buffer_info;

#ifdef DEBUG
    fprintf(stderr, "[DEBUG] enqueue buffer #%d...", buf->index);
#endif

    uint16_t takes = read_unbuffered? (device->input_buffer_num + 1) : 1;
    for (; takes>0; --takes)
    {
        // queue the spared (last) input buffer
        if (ioctl(device->fd, VIDIOC_QBUF, buf))
        {
            device->error_code = errno;
            strcpy(device->error_cause, "failed to re-queue input buffer");
            return Failure;
        }

        // generate a software trigger (in case it is requested)
        if (device->triggered && software_trigger
            && (capture_fire_software_trigger(device) != Success)) {
            return Failure;
        }

#ifdef DEBUG
        fprintf(stderr, "wait for an image to be written...");
#endif

        // select-based wait
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(device->fd, &fds);

        while(select(device->fd+1, &fds, NULL, NULL, NULL) < 0);

        if (FD_ISSET(device->fd, &fds)) {
            // dequeue the input buffer
            if (ioctl(device->fd, VIDIOC_DQBUF, buf))
            {
                device->error_code = errno;
                strcpy(device->error_cause, "failed to dequeue input buffer");
                return Failure;
            }
        }
    }

    // copy the frame into user space
#ifdef DEBUG
    fprintf(stderr, "copying...");
#endif
    memcpy(device->stored, device->input_buffer[buf->index], buf->bytesused);

#ifdef DEBUG
    fprintf(stderr, "done.\n");
#endif
    return Success;
}

int capture_stop(Device* device)
{
    switch(device->status)
    {
        case DeviceIsNotAvailable:
            device->error_code = EINVAL;
            strcpy(device->error_cause, "device is closed or not available");
            return Success;
        case DeviceIsIdle:
            device->error_code = EINVAL;
            strcpy(device->error_cause, "device has not been capturing");
            return Success;
        case DeviceIsCapturing:
            break;
    }

#ifdef DEBUG
    fprintf(stderr, "[DEBUG] stopping capture...");
#endif

    enum v4l2_buf_type type;
    type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (ioctl(device->fd, VIDIOC_STREAMOFF, &type))
    {
        device->error_code = errno;
        strcpy(device->error_cause, "failed to stop capturing");
        return Failure;
    }
    free_input_buffers(device, device->input_buffer_num);
#ifdef DEBUG
    fprintf(stderr, "success.\n");
#endif
    device->status = DeviceIsIdle;
    return Success;
}
