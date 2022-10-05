#
# Description: Build CRUX-ARM releases
#
# The first objective for this script is to generate a generic release (i.e: crux-arm-3.7.rootfs.tar.xz)
# But also it will run from ARM compatible devices to generate optimized releases (i.e: crux-arm-3.7.rootfs.odroidxu4.tar.xz)

CRUX_ARM_VERSION = 3.7
CRUX_ARM_GIT_PREFIX = https://github.com/crux-arm
CRUX_GIT_PREFIX = git://crux.nu/ports

WORKSPACE_DIR = $(dir $(abspath $(firstword $(MAKEFILE_LIST))))

PORTS_DIR = $(WORKSPACE_DIR)ports
ROOTFS_DIR = $(WORKSPACE_DIR)rootfs

PORTS_STAGE0_FILE = $(WORKSPACE_DIR)ports.stage0
PORTS_STAGE1_FILE = $(WORKSPACE_DIR)ports.stage1

# stage0 ports are the minimal base for creating a chroot where continue building ports
PORTS_STAGE0 = automake bash binutils coreutils dash diffutils file filesystem findutils gawk gettext \
	gcc grep glibc gzip libtool m4 make patch perl pkgconf pkgutils prt-get python3 sed tar

PORTS_BLACKLIST = glibc-32

PKGMK_CONFIG_FILE = $(WORKSPACE_DIR)pkgmk.conf
PKGMK_COMPRESSION_MODE = "xz"

PRTGET_CONFIG_FILE = $(WORKSPACE_DIR)prt-get.conf

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
else ifeq ("$(DEVICE_OPTIMIZATION)", "raspberrypi3")
COLLECTIONS = raspberrypi3-arm64 core-arm64 core
endif

# Use fakeroot command to build packages
ifeq ($(PKGMK_FAKEROOT),yes)
PKGMK_COMMAND = fakeroot pkgmk
else
PKGMK_COMMAND = pkgmk
endif

# Force pkgmk to rebuilt packages
ifeq ($(PKGMK_FORCE),yes)
PKGMK_CMD_OPTS = -is -f
else
PKGMK_CMD_OPTS = -is
endif

.PHONY: help
help:
	@echo "Targets:"
	@echo '  help                        Show this help information'
	@echo '  build PORTS="port1 port2"   Build ports in order'
	@echo '  stage0                      Build stage0 ports'
	@echo '  stage1                      Build stage1 ports (inside a chroot environment)'
	@echo '  bootstrap                   Build all stages'
	@echo '  release                     Build CRUX-ARM release'

.PHONY: check-root
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

# Clones all COLLECTIONS of ports required to generate the release
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

.PHONY: clean-pkgmkconf
clean-pkgmkconf: $(PKGMK_CONFIG_FILE)
	@rm -f $(PKGMK_CONFIG_FILE)

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

.PHONY: clean-prtgetconf
clean-prtgetconf: $(PRTGET_CONFIG_FILE)
	@rm -f $(PRTGET_CONFIG_FILE)

# Generates ports.stage0 (list of ports required to create the stage0)
.PHONY: prepare-stage0-file
prepare-stage0-file: $(PORTS_DIR) $(PRTGET_CONFIG_FILE)
	@prt-get --config=$(PRTGET_CONFIG_FILE) quickdep $(PORTS_STAGE0) > $(PORTS_STAGE0_FILE)
$(PORTS_STAGE0_FILE): prepare-stage0-file

.PHONY: clean-stage0-file
clean-stage0-file: $(PORTS_STAGE0_FILE)
	@rm -f $(PORTS_STAGE0_FILE)

# Generates ports.stage1 (list of ports required to create the stage1)
.PHONY: prepare-stage1-file
prepare-stage1-file: $(PORTS_DIR) $(PRTGET_CONFIG_FILE)
	@prt-get --config=$(PRTGET_CONFIG_FILE) list > $(PORTS_STAGE1_FILE).tmp
	@for bl in $(PORTS_BLACKLIST); do \
		sed "/^$$bl/d" -i $(PORTS_STAGE1_FILE).tmp; \
	done
	@prt-get --config=$(PRTGET_CONFIG_FILE) quickdep `cat $(PORTS_STAGE1_FILE).tmp | tr '\n' ' '` > $(PORTS_STAGE1_FILE)
	@rm -f $(PORTS_STAGE1_FILE).tmp
$(PORTS_STAGE1_FILE): prepare-stage1-file

.PHONY: clean-stage1-file
clean-stage1-file: $(PORTS_STAGE1_FILE)
	@rm -f $(PORTS_STAGE1_FILE)

# Download port sources specified by input variable PORTS
.PHONY: download
download: $(PKGMK_CONFIG_FILE) $(PRTGET_CONFIG_FILE)
	@for PORT in $(PORTS); do \
		echo "[`date +'%F %T'`] Download sources for port: $$PORT" ; \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		( cd $$portdir && $(PKGMK_COMMAND) -do -cf $(PKGMK_CONFIG_FILE)); \
	done

# Build ports specified by input variable PORTS
.PHONY: build
build: check-optimization $(PKGMK_CONFIG_FILE) $(PRTGET_CONFIG_FILE)
	@for PORT in $(PORTS); do \
		echo "[`date +'%F %T'`] Building port: $$PORT" ; \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		( cd $$portdir && $(PKGMK_COMMAND) -d -cf $(PKGMK_CONFIG_FILE) $(PKGMK_CMD_OPTS) ); \
	done

# Build ports and install them specified by input variable PORTS
.PHONY: build-and-install
build-and-install: check-optimization $(PKGMK_CONFIG_FILE) $(PRTGET_CONFIG_FILE)
	@for PORT in $(PORTS); do \
		echo "[`date +'%F %T'`] Building port: $$PORT" ; \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		( cd $$portdir && $(PKGMK_COMMAND) -d -cf $(PKGMK_CONFIG_FILE) $(PKGMK_CMD_OPTS) ); \
		( prt-get --config=$(PRTGET_CONFIG_FILE) install $$PORT || prt-get --config=$(PRTGET_CONFIG_FILE) update $$PORT ); \
	done

# Create a tar file with stage0 packages
.PHONY: backup-packages-stage0
backup-packages-stage0:
	@echo "[`date +'%F %T'`] Backup packages from stage0"
	@cd $(PORTS_DIR) && tar cf $(WORKSPACE_DIR)packages.stage0.tar `find . -type f -name "*.pkg.tar.$(PKGMK_COMPRESSION_MODE)"`

#------------------------------------------------------------------------------
# STAGE0
#
# Build toolchain ports
#
.PHONY: stage0
stage0: $(PORTS_STAGE0_FILE)
	$(MAKE) build PORTS="`cat $(PORTS_STAGE0_FILE)`" PKGMK_FAKEROOT=yes

#------------------------------------------------------------------------------
# STAGE1
#
# - Download sources for all ports in stage1 (to avoid use wget/curl inside the chroot)
#   On stage0, ports are compiled and linked against the host. So stage0 packages may have broken dependencies
#   and may fail when running inside a chroot environment.
#
# - Create rootfs with packages built in stage0
#
# - Chroot into rootfs and build all ports
#
.PHONY: stage1
stage1: backup-packages-stage0 $(PORTS_STAGE0_FILE) $(PORTS_STAGE1_FILE) $(PKGMK_CONFIG_FILE) $(PRTGET_CONFIG_FILE)
	@echo "[`date +'%F %T'`] Download port sources"
	@for PORT in `cat $(PORTS_STAGE1_FILE)`; do \
		echo "[`date +'%F %T'`] - port: $$PORT" ; \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		( cd $$portdir && $(PKGMK_COMMAND) -do -cf $(PKGMK_CONFIG_FILE)); \
	done
	@echo "[`date +'%F %T'`] Creating rootfs for stage1 in $(ROOTFS_DIR)"
	@sudo mkdir -p $(ROOTFS_DIR)
	@sudo mkdir -p $(ROOTFS_DIR)/var/lib/pkg
	@sudo touch $(ROOTFS_DIR)/var/lib/pkg/db
	@for PORT in `cat $(PORTS_STAGE0_FILE)`; do \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		package=`find $$portdir -type f -name "$$PORT#*.$(PKGMK_COMPRESSION_MODE)"`; \
		echo "[`date +'%F %T'`] - package: $$package"; \
		sudo pkgadd -r $(ROOTFS_DIR) $$package; \
	done
	@echo "[`date +'%F %T'`] Installing extras"
	@sudo cp -L /etc/resolv.conf $(ROOTFS_DIR)/etc/resolv.conf
	@sudo ln -sf /workspace/pkgmk.conf $(ROOTFS_DIR)/etc/pkgmk.conf
	@sudo ln -sf /workspace/prt-get.conf $(ROOTFS_DIR)/etc/prt-get.conf
	@echo "[`date +'%F %T'`] Installing hacks to avoid host dependencies"
	@sudo ln -sf libnsl.so.3 $(ROOTFS_DIR)/usr/lib/libnsl.so.2
	@echo "[`date +'%F %T'`] Preparing chroot environment ($(ROOTFS_DIR))"
	@echo "[`date +'%F %T'`] - Mounting /dev on $(ROOTFS_DIR)/dev"
	@sudo mount --bind /dev $(ROOTFS_DIR)/dev
	@echo "[`date +'%F %T'`] - Mounting /proc on $(ROOTFS_DIR)/proc"
	@sudo mount --bind /proc $(ROOTFS_DIR)/proc
	@echo "[`date +'%F %T'`] - Mounting $(WORKSPACE_DIR) on $(ROOTFS_DIR)/workspace"
	@sudo mkdir $(ROOTFS_DIR)/workspace
	@sudo mount --bind $(WORKSPACE_DIR) $(ROOTFS_DIR)/workspace
	@echo "[`date +'%F %T'`] Entering chroot enrivonment"
	@PORTS="`cat $(PORTS_STAGE1_FILE)`"
	@sudo chroot $(ROOTFS_DIR) /bin/bash --login -c \
		"cd /workspace && $(MAKE) build-and-install PORTS=\"`cat $(PORTS_STAGE1_FILE)`\" PKGMK_FORCE=yes" || exit 0
	@echo "[`date +'%F %T'`] Exiting chroot enrivonment"
	@echo "[`date +'%F %T'`] - Unmounting $(ROOTFS_DIR)/workspace"
	@sudo umount $(ROOTFS_DIR)/workspace
	@sudo rmdir $(ROOTFS_DIR)/workspace
	@echo "[`date +'%F %T'`] - Unmounting $(ROOTFS_DIR)/proc"
	@sudo umount $(ROOTFS_DIR)/proc
	@echo "[`date +'%F %T'`] - Unmounting $(ROOTFS_DIR)/dev"
	@sudo umount $(ROOTFS_DIR)/dev

.PHONY: bootstrap
bootstrap:
	@echo "[`date +'%F %T'`] Bootstrap started"
	@echo "[`date +'%F %T'`] - Stage 0"
	$(MAKE) stage0
	@echo "[`date +'%F %T'`] - Stage 1"
	$(MAKE) stage1
	@echo "[`date +'%F %T'`] Bootstrap completed"

# TODO: upload release to mirror
.PHONY: release
release: $(ROOTFS_DIR)
	$(MAKE) bootstrap
	@cd $(ROOTFS_DIR) && tar cvJf ../crux-arm-$(CRUX_ARM_VERSION).rootfs.tar.xz *

# TODO: upload packages to mirror
.PHONY: release-packages
release-packages: $(PORTS)
	@find $(PORTS) -type f -name '*.pkg.tar.$(PKGMK_COMPRESSION_MODE)'
