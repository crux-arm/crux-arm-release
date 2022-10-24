# This is a generic optimization for aarch64-linux-gnu
# For 64-bit based devices, targeting armv8 architecture

# Generic compiler options for aarch64-linux-gnu
CFLAGS = -O2 -pipe

# Port collections required to build a generic arm64 release
COLLECTIONS = core-arm64 core

# Release file
RELEASE_TAR_FILE = crux-arm-$(CRUX_ARM_VERSION)-aarch64.rootfs.tar.xz
