#
# run with: `fakeroot make bootstrap`
#
#
# Description: Build CRUX-ARM releases
#
# The first objective for this script is to generate a generic release (i.e: crux-arm-3.7.rootfs.tar.xz)
# But also it will run from ARM compatible devices to generate optimized releases (i.e: crux-arm-3.7.rootfs.odroidxu4.tar.xz)

CRUX_ARM_VERSION = 3.7
CRUX_ARM_GIT_PREFIX = https://github.com/crux-arm
CRUX_GIT_PREFIX = git://crux.nu/ports

PORTS_DIR = $(PWD)/ports
ROOTFS_DIR = $(PWD)/rootfs

PORTS_LIST_FILE = $(PWD)/ports.list
PORTS_DEPS_FILE = $(PWD)/ports.deps
PORTS_ORDER_FILE = $(PWD)/ports.order

PORTS_BLACKLIST = glibc-32

PKGMK_CONFIG_FILE = $(PWD)/pkgmk.conf
PKGMK_COMPRESSION_MODE = "xz"

PRTGET_CONFIG_FILE = $(PWD)/prt-get.conf

# Optimization based on devices
DEVICE_OPTIMIZATION = arm
# Load CFLAGS for selected optimization (default: arm.mk)
include $(DEVICE_OPTIMIZATION).mk

# COLLECTIONS (port overlays) for each optimization
#
# This is a generic optimization for arm-linux-gnueabihf
# For 32-bit based devices, using the hard-float version
# of the "new" ABI (EABI), targeting armv7 and up
ifeq ("$(DEVICE_OPTIMIZATION)", "arm")
COLLECTIONS = core-arm core
# Optimization for Odroid XU4 devices
else ifeq ("$(DEVICE_OPTIMIZATION)", "odroidxu4")
COLLECTIONS = odroidxu4-arm core-arm core
# This is a generic optimization for aarch64-linux-gnu
# For 64-bit based devices, targeting armv8 architecture
else ifeq ("$(DEVICE_OPTIMIZATION)", "arm64")
COLLECTIONS = core-arm64 core
# Optimization for RaspberryPi 4 devices
else ifeq ("$(DEVICE_OPTIMIZATION)", "raspberrypi4")
COLLECTIONS = raspberrypi4-arm64 core-arm64 core
endif

# Force pkgmk to rebuilt packages
ifeq ($(FORCE),yes)
PKGMK_FORCE=-f
else
PKGMK_FORCE=
endif

.PHONY: help
help:
	@echo "Targets:"
	@echo "  help"
	@echo "  print-order   Retrieve a list of collection and ports in order to be built"
	@echo "  build-ports   Build ports in order"
	@echo "  chroot-ports  Build ports in order inside a chroot environment"
	@echo "  bootstrap     Build all stages"

check-root:
	@if [ "$(shell id -u)" != "0" ]; then \
		echo "You need to be root to do this."; \
		exit 1; \
	fi

.PHONY: check-optimization
check-optimization:
	@if [ "$(shell uname -m)" != "aarch64" ]; then \
		found=0; \
		for COLL in $(COLLECTIONS); do \
			case $$COLL in \
				core-arm64) found=1 ;; \
				*) found=0 ;; \
			esac \
		done; \
		if [ $$found -eq 1 ]; then \
			echo "Your host is not able to build an optimization for $(DEVICE_OPTIMIZATION)"; \
			exit 1; \
		fi \
	fi

# TODO: Use tags or branches to have an static or updated release
.PHONY: prepare-ports
prepare-ports:
	@for COLL in $(COLLECTIONS); do \
		if [ ! -d $(PORTS_DIR)/$$COLL ]; then \
			case $$COLL in \
				core) git clone -b $(CRUX_ARM_VERSION) --single-branch $(CRUX_GIT_PREFIX)/$$COLL $(PORTS_DIR)/$$COLL ;; \
				*-arm|*-arm64) git clone -b $(CRUX_ARM_VERSION) --single-branch $(CRUX_ARM_GIT_PREFIX)/crux-ports-$$COLL $(PORTS_DIR)/$$COLL ;; \
			esac \
		fi \
	done
$(PORTS_DIR): prepare-ports

# Generates pkgmk.conf
.PHONY: prepare-pkgmkconf
prepare-pkgmkconf:
	@echo "export CFLAGS=\"$(CFLAGS)\"" > $(PKGMK_CONFIG_FILE)
	@echo "export CXXFLAGS=\"$(CFLAGS)\"" >> $(PKGMK_CONFIG_FILE)
	@echo "PKGMK_COMPRESSION_MODE=\"$(PKGMK_COMPRESSION_MODE)\"" >> $(PKGMK_CONFIG_FILE)
$(PKGMK_CONFIG_FILE): prepare-pkgmkconf

# Generates prt-get.conf
.PHONY: prepare-prtgetconf
prepare-prtgetconf: $(PORTS_DIR)
	@:> $(PRTGET_CONFIG_FILE)
	@for COLL in $(COLLECTIONS); do \
		echo "prtdir $(PORTS_DIR)/$$COLL" >> $(PRTGET_CONFIG_FILE); \
	done
	@echo "rmlog_on_success no" >> $(PRTGET_CONFIG_FILE)
	@echo "runscripts yes" >> $(PRTGET_CONFIG_FILE)
$(PRTGET_CONFIG_FILE): prepare-prtgetconf

.PHONY: prepare-portslist
prepare-portslist: $(PORTS_DIR) $(PRTGET_CONFIG_FILE)
	@prt-get --config=$(PRTGET_CONFIG_FILE) list > $(PORTS_LIST_FILE)
	@for bl in $(PORTS_BLACKLIST); do \
		sed "/^$$bl/d" -i $(PORTS_LIST_FILE); \
	done
$(PORTS_LIST_FILE): prepare-portslist

# Generates a list of port dependencies calculated with prt-get and overlays
.PHONY: prepare-portsdeps
prepare-portsdeps: $(PORTS_LIST_FILE)
	@while read PORT; do \
		echo -n $$PORT": "; \
		prt-get --config=$(PRTGET_CONFIG_FILE) quickdep $$PORT; \
	done < $(PORTS_LIST_FILE) > $(PORTS_DEPS_FILE)
$(PORTS_DEPS_FILE): prepare-portsdeps

# Generates a list of ports in order to be built
.PHONY: prepare-portsorder
prepare-portsorder: $(PORTS_LIST_FILE)
	@prt-get --config=$(PRTGET_CONFIG_FILE) quickdep `cat $(PORTS_LIST_FILE)` > $(PORTS_ORDER_FILE)
$(PORTS_ORDER_FILE): prepare-portsorder

# Prints a list of collection/port in order to be built
.PHONY: print-order
print-order: $(PORTS_ORDER_FILE)
	@for PORT in `cat $(PORTS_ORDER_FILE)`; do \
		prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT" | sed "s|$(PORTS_DIR)/||"; \
	done

# This will be called lately in stages inside chroot
.PHONY: build-ports
build-ports: check-root check-optimization $(PORTS_ORDER_FILE) $(PRTGET_CONFIG_FILE) $(PKGMK_CONFIG_FILE)
	@echo "[`date +'%F %T'`] Building ports"
	@for PORT in `cat $(PORTS_ORDER_FILE)`; do \
		echo "[`date +'%F %T'`] - Port: $$PORT"; \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		cd $$portdir && pkgmk -d -cf $(PKGMK_CONFIG_FILE) $(PKGMK_FORCE); \
	done

# Create a rootfs with built packages and chroot to it
.PHONY: chroot-ports
chroot-ports: check-root check-optimization $(PORTS_ORDER_FILE) $(PRTGET_CONFIG_FILE)
	@echo "[`date +'%F %T'`] Creating chroot environment: $(ROOTFS_DIR)"
	@rm -rf $(ROOTFS_DIR)
	@mkdir -p $(ROOTFS_DIR)
	@echo "[`date +'%F %T'`] Installing packages"
	@mkdir -p $(ROOTFS_DIR)/var/lib/pkg
	@touch $(ROOTFS_DIR)/var/lib/pkg/db
	@for PORT in `cat $(PORTS_ORDER_FILE)`; do \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		find $$portdir -type f -name *.pkg.tar.$(PKGMK_COMPRESSION_MODE) | while read package; do \
			echo "[`date +'%F %T'`] - Package: `basename $$package` (collection: `dirname $$PORT`)"; \
			pkgadd -r $(ROOTFS_DIR) $$package; \
		done; \
	done
	@echo "[`date +'%F %T'`] Installing extras"
	@cp -L /etc/resolv.conf $(ROOTFS_DIR)/etc/
	@cp -L $(PKGMK_CONFIG_FILE) $(ROOTFS_DIR)/etc/
	@cp -L $(PRTGET_CONFIG_FILE) $(ROOTFS_DIR)/etc/
	@echo "[`date +'%F %T'`] Preparing chroot environment"
	@echo "[`date +'%F %T'`] - Mounting /dev on $(ROOTFS_DIR)/dev"
	@mount --bind /dev $(ROOTFS_DIR)/dev
	@echo "[`date +'%F %T'`] - Mounting /proc on $(ROOTFS_DIR)/proc"
	@mount --bind /proc $(ROOTFS_DIR)/proc
	@echo "[`date +'%F %T'`] - Mounting $$PWD on $(ROOTFS_DIR)/workspace"
	@mkdir $(ROOTFS_DIR)/workspace
	@mount --bind $$PWD $(ROOTFS_DIR)/workspace
	@echo "[`date +'%F %T'`] Entering chroot enrivonment"
	@chroot $(ROOTFS_DIR) /bin/bash --login -c "cd /workspace && $(MAKE) FORCE=yes build-ports"
	@echo "[`date +'%F %T'`] Exiting chroot enrivonment"
	@echo "[`date +'%F %T'`] - Unmounting $(ROOTFS_DIR)/workspace"
	@umount $(ROOTFS_DIR)/workspace
	@rmdir $(ROOTFS_DIR)/workspace
	@echo "[`date +'%F %T'`] - Unmounting $(ROOTFS_DIR)/proc"
	@umount $(ROOTFS_DIR)/proc
	@echo "[`date +'%F %T'`] - Unmounting $(ROOTFS_DIR)/dev"
	@umount $(ROOTFS_DIR)/dev
	@echo "[`date +'%F %T'`] Removing chroot environment"
	@rm -rf $(ROOTFS_DIR)

bootstrap: check-root
	@echo "[`date +'%F %T'`] Bootstrap started"
	@echo "[`date +'%F %T'`] - Stage 0"
	@$(MAKE) build-ports
	@echo "[`date +'%F %T'`] - Stage 1"
	@$(MAKE) chroot-ports
	@echo "[`date +'%F %T'`] Bootstrap completed"

#
# TODO: work in progress
#