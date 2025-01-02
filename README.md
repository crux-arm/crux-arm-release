# CRUX-ARM Release

This project aims to create custom CRUX-ARM releases for specific ARM architectures. The release creation process is automated using a Makefile to build the necessary packages and generate a root filesystem for ARM-based devices.


## Index

- [Overview](#overview)
- [Supported Architectures](#supported-architectures)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [Clone the Repository](#clone-the-repository)
  - [Set Up Environment](#set-up-environment)
  - [Bootstrap Process](#bootstrap-process)
- [Customizing the Build](#customizing-the-build)
- [Directory Structure](#directory-structure)
- [Root Filesystem Stages: `rootfs-stage0` vs. `rootfs-stage1`](#root-filesystem-stages-rootfs-stage0-vs-rootfs-stage1)
- [Contributing](#contributing)
  - [How to Contribute](#how-to-contribute)
- [License](#license)
- [Acknowledgements](#acknowledgements)


## Overview

The release process is split into several stages:

1. **Stage 0**:
    - The required packages (from upstream CRUX core and CRUX ARM overlay variants) are compiled.
    - These packages are installed in the `rootfs-stage0` directory.

2. **Stage 1**:
    - Using the packages from **Stage 0**, the system is chrooted into a fresh environment to build additional packages.
    - These packages are installed in the `rootfs-stage1` directory.

3. **Release Creation**:
    - The contents of `rootfs-stage1` are packaged into a compressed archive (`crux-arm-VERSION.rootfs.tar.xz`) to create the final CRUX-ARM release.

The goal is to streamline the process of building a minimal, stable CRUX system tailored for ARM-based architectures.


## Supported Architectures

- `arm64` (aarch64 - 64-bit ARM architecture)
- `arm` (armhf - 32-bit ARM architecture with hard-float support)


## Prerequisites

To build the CRUX-ARM release, there are two approaches: Native and Dockerized.

### Native
- Preferably requires a CRUX-ARM Linux system for the variant of the release you want to build (`arm64` or `arm`).
- Alternatively, you can use Arch or Debian for ARM (or similar distributions). In this case, ensure that the basic tools `make`, `gcc`, `git`, `xz`, and necessary development headers and libraries are installed.

### Dockerized (and non-Native)
- You can build the CRUX-ARM release on CRUX Linux for `x86_64` or even on other Linux distributions or macOS capable of running multi-arch Docker containers.
- The `tools/dockerize.sh` script will handle the process inside a Docker container, abstracting the need for a native ARM environment. For example, to run the bootstrap it would be something like:
    ```bash
    tools/dockerize.sh bootstrap
  ```
- Note tha to run an `arm64` (or `armhf`) container from a different architecture host (e.g. `x86_64`), you must enable multi-architecture support using QEMU.
  Ensure that Docker and QEMU are installed, then run:
    ```bash
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
    ```
    This command registers QEMU to handle non-native architectures. After that, you can run an `arm64` (or `armhf`) container like this to verify that everything is working fine:
    ```bash
    # on arm64
    docker run --rm --platform linux/arm64 -t sepen/crux:arm64 bash -c "uname -m"
    # on armhf
    #docker run --rm --platform linux/arm/v7 -t sepen/crux:armhf bash -c "uname -m"
    ```

For both approaches, ensure your system has internet access to the upstream CRUX repositories for both core and ARM-specific ports.


## Getting Started

To begin the process of building the CRUX-ARM release, follow these steps:

### Clone the Repository

First, clone this repository to your local machine:

```bash
git clone https://github.com/crux-arm/crux-arm-release.git
cd crux-arm-release
git checkout <branch> # e.g. 3.8
```

### Set Up Environment
Depending on your target architecture, you can specify the device optimization during the build by setting the OPTIMIZED_DEVICE variable. By default, this is set to arm64.

### Bootstrap Process
Run the Makefile to start the bootstrap process:

```bash
make bootstrap
```

This will trigger the following Makefile targets:

1. **`stage0`**: It will build the necessary base packages from upstream CRUX and ARM repositories for the selected architecture.
2. **`stage1`**: After **Stage 0** completes, the system will automatically enter a chroot environment where additional packages will be compiled.
3. **`release`**: The final root filesystem will be packaged as `crux-arm-VERSION.rootfs.tar.xz`, where VERSION will be replaced by the version of the release.

You can run `make bootstrap` to trigger the entire process or alternatively you can run individual stages by using:
```
make stage0
make stage1
make release
```

Run `make help` to see all available Makefile options and commands.


## Customizing the Build

You can customize the build by specifying a different optimized device. The default value for **OPTIMIZED_DEVICE** is `arm64`.

To see the list of other supported optimizations, browse the [devices](devices/) folder in this repository. Each `*.mk` file corresponds to a specific ARM device optimization, and you can select the one that matches your target hardware (or contribute a new one).

Example Build for another device optimization (e.g., raspberrypi4)
```bash
make bootstrap OPTIMIZED_DEVICE=raspberrypi4
```

This will build the release with the optimizations specified for the chosen device.


## Directory Structure

The following directories are involved in the build process:

- **`devices`**: Contains configuration and optimization files for various supported ARM devices.
- **`ports`**: Stores a clone of the upstream CRUX core ports and additional overlays for specific ARM architectures (e.g., core-arm64, core-armhf) and device-specific optimizations (e.g., raspberrypi4-arm64).
- **`rootfs-stage0`**: Contains the initial bootstrap environment and packages from **Stage 0**.
- **`rootfs-stage1`**: Contains the packages and configurations created during **Stage 1**.

Both `rootfs-stage0` and `rootfs-stage1` are created during the build process (usually executed via make). These stages are progressively populated with files and utilities to prepare the root filesystem.

## Root Filesystem Stages: `rootfs-stage0` vs. `rootfs-stage1`

### **rootfs-stage0**: (No Device-Specific Optimizations)

This is the **first stage** of creating a root filesystem. It contains a **generic, unoptimized set of packages** that are suitable for `arm64` or `armhf` architecture and do not include device-specific optimizations.

This stage contains a **generic and unoptimized** root filesystem. The goal is to set up a **working environment** with minimal setup, where packages are compiled or installed without any optimizations for the target device.

#### Key Characteristics:
- Packages are installed **without architecture or device-specific optimizations**.
- **Generic** compiler flags (e.g., `-O2 -pipe`) are used to ensure portability across different systems.
- Contains the **minimum set of packages** like `gcc`, `glibc`, `binutils`, etc. and basic libraries.
- The focus is on getting a **basic root filesystem** up and running, not on optimizing for performance or power efficiency.

#### During the Build Process:
- Basic tools and libraries are installed without performance optimizations.
- This stage is typically **faster to build** but results in a system that might not be efficient for your target hardware.

### **rootfs-stage1**: Device-Specific Optimizations

This stage applies **device-specific optimizations** to the root filesystem. It is typically built **on the target device** (or in a similar cross-compilation environment) to ensure that the system is **tailored for the architecture** and hardware features of the device.

#### Key Characteristics:
- Packages are **recompiled or reconfigured with device-specific optimizations** (e.g., CPU architecture flags, hardware-specific libraries).
- The system is compiled using **architecture-specific flags** (e.g., `-march=armv8-a+crc+simd -mtune=cortex-a72` for tuning binaries for the device’s CPU).
- Optimizations include considerations for **performance**, **power consumption**, and **memory usage**.
- System libraries and applications are built to be as **efficient** as possible for the target device’s hardware.

#### During the Build Process:
- **Device-specific flags** are used, such as `-march=armv7-a` for armhf or `-mfpu=neon-vfpv4` for optimization.
- Additional device-specific drivers and libraries may be included.
- The root filesystem is optimized for performance, making it **smaller, faster, and more power-efficient**.

### Typical Workflow

1. **Built rootfs-stage0** on a development machine (or a neutral environment).
    ```bash
    make rootfs-stage0
    ```
    - At this point, the build contains generic packages with no optimizations for the target hardware.

2. **Transfer to Target Device**: (Optional if built on host)
    - If building on a host machine, the root filesystem is copied to the target device.

3. **Built rootfs-stage1** on the target device, ensuring the system is **optimized for the device's hardware**.
    ```bash
    make rootfs-stage1
    ```
    - This stage compiles the packages with architecture-specific flags and optimizations, making the system more efficient for the target device.

4. **Finalize the Build** (Optional further stages):
    - You may proceed with additional stages (like `release`) to complete the root filesystem.
    ```bash
    make release
    ```

## Contributing

Contributions to the project are welcome. If you find bugs, or have suggestions for improvements, please open an issue or submit a pull request.


### How to Contribute

1. Fork the repository.
2. Create a feature branch.
3. Commit your changes.
4. Push your branch to your forked repository.
5. Open a pull request to the main repository.

Please ensure that all changes maintain the project's standards and include necessary tests or documentation.


## License

This project is licensed under the GPLv3 License - see the [LICENSE](LICENSE) file for details.


## Acknowledgements

Thanks to the CRUX community and the CRUX-ARM community for their continued contributions and support.
