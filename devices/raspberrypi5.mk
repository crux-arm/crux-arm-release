CRUX_ARM_ARCH = arm64
CFLAGS = -O2 -mlittle-endian -mabi=lp64 -march=armv8.2-a+crypto+fp16+rcpc+dotprod -fasynchronous-unwind-tables
COLLECTIONS = raspberrypi5-arm64 core-arm64 core
