# This is a generic optimization for arm-linux-gnueabihf
# For 32-bit based devices, using the hard-float version
# of the "new" ABI (EABI), targeting ARMv7 and up

# Generic compiler options for arm-linux-gnueabihf
CFLAGS = -O2 -pipe -march=armv7-a -mfloat-abi=hard -mfpu=vfpv3 -fPIC

# Port collections required to build a generic arm release
COLLECTIONS = core-arm core

# Release file
RELEASE_TAR_FILE = crux-arm-$(CRUX_ARM_VERSION)-armhf.rootfs.tar.xz
