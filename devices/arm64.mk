# This is a generic optimization for arm64
# For 64-bit based devices, targeting ARMv8 architecture

# Generic compiler options for arm64 (aarch64-unknown-linux-gnu)
#
# -march=armv8-a  – Targets the ARMv8-A architecture, which is the most common
#                   64-bit ARM architecture.
# -fPIC           – Ensures Position Independent Code (PIC), which is necessary
#                   for creating shared libraries on ARM64 systems.
CFLAGS = -O2 -pipe -march=armv8-a -fPIC

# Port collections required to build a generic arm64 release
COLLECTIONS = core-arm64 core

# Release file
RELEASE_TAR_FILE = crux-arm-$(CRUX_ARM_VERSION)-arm64.rootfs.tar.xz
