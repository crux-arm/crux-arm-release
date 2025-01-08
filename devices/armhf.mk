# This is a generic optimization for armhf
# For 32-bit based devices, using the hard-float version
# of the "new" ABI (EABI), targeting ARMv7 and up

# Generic compiler flags for armhf (arm-unknown-linux-gnueabihf)
#
# -march=armv7-a   – Targets ARMv7-A architecture (generic for armhf).
# -mfloat-abi=hard – Uses hardware floating-point ABI (required for armhf).
# -mfpu=vfpv3-d16  – Configures the FPU to VFPv3 with 16 registers (common for ARMv7).
#                    If the device supports NEON, you can use -mfpu=neon.
# -fPIC            - Ensures Position Independent Code (PIC), which is necessary
#                    for creating shared libraries on ARMv7 systems.
CFLAGS = -O2 -pipe -march=armv7-a -mfloat-abi=hard -mfpu=vfpv3 -fPIC

# Port collections required to build a generic armhf release
COLLECTIONS = core-arm core

# Release file
RELEASE_TAR_FILE = crux-arm-$(CRUX_ARM_VERSION)-armhf.rootfs.tar.xz
