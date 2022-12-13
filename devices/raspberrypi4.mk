CFLAGS = -march=armv8-a+crc+simd -mtune=cortex-a72 -ftree-vectorize -O2 -pipe -fomit-frame-pointer
COLLECTIONS = raspberrypi4-arm64 core-arm64 core
RELEASE_TAR_FILE = crux-arm-$(CRUX_ARM_VERSION)-aarch64-raspberrypi4.rootfs.tar.xz
