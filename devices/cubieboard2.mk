CFLAGS=-O2 -pipe -mcpu=cortex-a7 -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard
COLLECTIONS = cubieboard2-arm core-arm core
RELEASE_TAR_FILE = crux-arm-$(CRUX_ARM_VERSION)-cubieboard2.rootfs.tar.xz
