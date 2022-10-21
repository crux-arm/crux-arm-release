# This is a generic optimization for arm-linux-gnueabihf
# For 32-bit based devices, using the hard-float version
# of the "new" ABI (EABI), targeting armv7 and up

# Generic compiler options for arm-linux-gnueabihf
CFLAGS = -O2 -pipe -mfloat-abi=hard

# Port collections required to build a generic arm release
COLLECTIONS = core-arm core