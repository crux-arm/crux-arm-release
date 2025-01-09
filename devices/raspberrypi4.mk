CRUX_ARM_ARCH = arm64
CFLAGS = -O2 -pipe -march=armv8-a+crc+simd -mtune=cortex-a72 -ftree-vectorize -fomit-frame-pointer
COLLECTIONS = raspberrypi4-arm64 core-arm64 core
