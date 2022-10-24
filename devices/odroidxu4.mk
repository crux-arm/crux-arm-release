CFLAGS = -O2 -pipe -mfloat-abi=hard -march=armv7ve -mtune=cortex-a15 -mfpu=neon-vfpv4
COLLECTIONS = odroidxu4-arm core-arm core
RELEASE_TAR_FILE = crux-arm-$(CRUX_ARM_VERSION)-odroidxu4.rootfs.tar.xz