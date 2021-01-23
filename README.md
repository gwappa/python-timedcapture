# timedcapture

a cython-based module to achieve on-time video capture through V4L2.

For a general usage, refer to [USAGE](https://github.com/gwappa/python-timedcapture/blob/master/USAGE.md).

## Prerequisites

**IMPORTANT NOTE**: the current implementation only allows 16-bit grayscale acquisition.
**IMPORTANT NOTE**: there is no functionality that controls the frame rate. Frame-capture timings must be controlled elsewhere, either using software or hardware timers.

- The library is tested on Ubuntu 18.04 LTS, but it is supposed to work on any Linux environment that runs V4L2.
- Please note that the library is optimized for cameras from [ImagingSource](https://www.theimagingsource.com/).
  By using devices from other manufacturers, you will not have control over functionalities such as:
  - 1 microsecond-order exposure control (V4L2 only allows the order of 10 microseconds)
  - auto-gain/manual-gain switch (the gain control will be totally manual- or auto-controlled)
  - trigger modes (by default, only the free-running mode will be allowed)
  - "strobe" output
  These settings must be configured elsewhere.

## Installation

```
pip install timedcapture
```

For the time being, we only provide the binary for the `x86_64` architecture.
To build it yourself, please refer to the section below.

## Compile by yourself

A working installation of Cython is required. Note that the recent versions of Cython requires Numpy over the version 1.17.

Clone the repository, and then run at the repository root:

```
python setup.py bdist_wheel
```

A `.whl` file will be created in the `dist` directory, which you can then use as `pip install xxx.whl`.

## License

2020 Keisuke Sehara, the MIT License.
