CFLAGS=-O2 -pipe -mfloat-abi=hard -mfpu=neon -mcpu=cortex-a8 -mtune=cortex-a8
COLLECTIONS = cubieboard-arm core-arm core
RELEASE_TAR_FILE = crux-arm-$(CRUX_ARM_VERSION).rootfs.tar.xz
