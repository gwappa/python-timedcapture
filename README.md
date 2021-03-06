# timedcapture

[![DOI](https://zenodo.org/badge/267508414.svg)](https://zenodo.org/badge/latestdoi/267508414)

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

Requires Python >=3.6 to work.

For the time being, we only provide the source distribution on PyPI.
You will need a working Cython and Numpy combination **pre-installed**.

```bash
$ pip install numpy>=1.19 cython>=0.29 # or: "conda install numpy cython", in case you use Anaconda
$ pip install timedcapture
```
Alternatively, you can visit our [releases page](https://github.com/gwappa/python-timedcapture/releases)
and download the x86_64 binary wheel.

You can install it via:

```bash
$ pip install timedcapture-<version...>.whl
```

## License

2020 Keisuke Sehara, the MIT License.

You can cite `timedcapture` by using the DOI: https://doi.org/10.5281/zenodo.4459207
