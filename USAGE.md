# Usage guide: timedcapture

## The Device class

**IMPORTANT NOTE**: the current implementation only allows 16-bit grayscale acquisition.

The class `timedcapture.Device` is exported as the interface to your video camera.
Upon initialization of the `Device` instance, `timedcapture` tries to open the device.

- specify the `path` to the device (e.g. `/dev/video0`) as the first argument.
- width/height settings can be passed as well (in addition to the control through properties).

The device remains open until you call its `close()` method.

## Typical workflow

**IMPORTANT NOTE**: there is no functionality that controls the frame rate. Frame-capture timings must be controlled elsewhere, either using software or hardware timers.

1. Open the device by instantiating a `Device`.
2. Configure your device by setting its properties.
3. Call `start_capture()` _before_ starting to read frames from the device.
4. Each `read_frame()` call afterwards will return a frame being captured in series.
5. (Optional) calling `stop_capture()` will end the frame-capture sequence whilst leaving the device open.
6. Call `close()` to free up all the resources.

## Properties

Below are the list of properties available on the `Device` class.
All integral values must be positive, unless otherwise specified.

### `path`

(read-only, `str`) the path to the device.

### `width`

(read/write, `int`) the width of the frames to be captured (only values allowed through the V4L2 interface will be accepted).


### `height`

(read/write, `int`) the height of the frames to be captured (only values allowed through the V4L2 interface will be accepted).

### `size`

(read/write) a tuple of (`width`, `height`).

### `exposure_us`

(read/write, `int`) the value of exposure.

### `gain`

(read/write, non-negative `int`) the V4L2 gain setting of the sensor.

### `triggered`

(read/write, `bool`) whether the camera waits for an external trigger to capture a frame. Setting `False` here means the camera captures frames in the "free-running" manner.

### `strobe`

(read/write, `bool`) enables the "strobe" output corresponding to the exposure.

### `nb_buffer`

(read/write, `int`) the number of frames in the buffer.

The buffer is formed in the first-in, first-out manner such that, if the camera acquires the frames A, B and C in this order, reading frames by the computer each time will yield the frames exactly in the same sequence (A, B, C).

Increasing this number (i.e. >=2) will reduce the time spent on each `read_frame()` call, but increase the overall latency from the time the frame is captured and the time it is read by the computer.

## Methods

Below are the list of methods available on the `Device` class (other than the initializer).

### `start_capture()`

Tell the underlying driver to start capturing. **You must call this method before starting to read frames, or the process will hang**.
The library also prepares necessary resources (e.g. frame buffer) at this point.

### `read_frame()`

Returns a single-frame data being wrapped as a `numpy.ndarray` object.

A few keyword arguments are available:

- `software_trigger`: (`bool`, default=`True`) if this value is set `True`, the method generates a software trigger by itself in case where `triggered == True`.
- `read_unbuffered`: (`bool`, default=`False`) whether or not to read an "unbuffered" frame. If this value is `True`, the library discards all the data in the frame buffer, and newly acquire a single frame from the device.
- `copy`: (`bool`, default=`False`) whether or not to copy the frame data when creating a `numpy.ndarray` object. If `False`, the resulting `numpy.ndarray` object will merely wrap the data buffer in the `Device` instance, and can hence get updated by the end of the next `read_frame()` call. On the other hand, if `copy` is set `True`, the resulting `numpy.ndarray` object will live independently of the `Device` instance, but it will take more time to return from the call.

### `stop_capture()`

Tell the underlying driver to stop capturing. The library releases the buffer at this point.

It can be called when you want to reset the capture parameters, but want to reuse the device in the same process. Otherwise, calling the `close()` method will automatically call this method.

### `close()`

Closes this device, and releases all the resources associated with it. If capturing is still running, the method also calls `stop_capture()` internally.

You cannot re-use the Device object after calling `close()`. Calling `close()` multiple times will not have any adverse effects.

## Considerations related to closed-loop capturing

### Timing

We recommend the use of **frame triggers** so that you have more control over when a frame is captured.

The easiest method will be the use of **software triggers**. By using it, you will tell the device to capture a frame only when you need it in your program. This method also has an advantage of "retrieving the most up-to-date image". On the other hand, you will have to manage when to generate software triggers with the aid of e.g. a timer algorithm.

The use of **external (hardware) triggers** will ensure capturing at the desired frame rate, but you will have to ensure that your program catches up well with the frequency of frame capture. Failing to do so will result in frame drops (if the frame buffer is not enough), or your computer running out of memory (if video encoding is too slow).

No matter the trigger mode, you can always enable the `strobe` output to monitor when your camera actually attempts to capture frames.

### Buffering

To enable your program to achieve a good closed-loop, on-time performance, you need to **set the number of frame buffer (i.e. `nb_buffer`) to 1**. Failing to so so will increase the total closed-loop latency as each `read_frame()` call will only return a frame that is a number of frames old.
