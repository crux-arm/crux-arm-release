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
PORTS_STAGE0 = automake attr bash binutils bison coreutils curl dash diffutils file \
	filesystem findutils gawk gettext gcc grep glibc gzip libtool m4 make openssl \
	patch perl pkgconf pkgutils prt-get python3 sed tar util-linux

# ports that will not take part in the release
PORTS_BLACKLIST = glibc-32 jsoncpp libuv lzlib rhash

PKGMK_CONFIG_FILE = $(WORKSPACE_DIR)pkgmk.conf
PKGMK_COMPRESSION_MODE = xz

PRTGET_CONFIG_FILE = $(WORKSPACE_DIR)prt-get.conf

# Optimization based on devices
DEVICE_OPTIMIZATION = arm
# Load CFLAGS and COLLECTIONS for selected optimization
include devices/$(DEVICE_OPTIMIZATION).mk

# Default build command
PKGMK_CMD = pkgmk
# Use fakeroot command to build packages
ifeq ($(PKGMK_FAKEROOT),yes)
PKGMK_CMD = fakeroot pkgmk
endif

# Default pkgmk options
PKGMK_CMD_OPTS = -is
# Force pkgmk to rebuilt packages
ifeq ($(PKGMK_FORCE),yes)
PKGMK_CMD_OPTS += -f
endif

.PHONY: help
help:
	@echo "Targets:"
	@echo '  help         Show this help information'
	@echo '  stage0       Build stage0 ports compiled against your host'
	@echo '  stage1       Build stage1 ports inside chroot environment'
	@echo '  bootstrap    Build all stages and bootstrap the rootfs'
	@echo '  release      Build CRUX-ARM release'
	@echo
	@echo 'Additional variables to all targets:'
	@echo
	@echo '  DEVICE_OPTIMIZATION  Device for which we want to optimize the build'
	@echo '                       e.g: make stage1 DEVICE_OPTIMIZATION=odroidxu4'

.PHONY: check-root
check-root:
	@if [ "$(shell id -u)" != "0" ]; then \
		echo "You need to be root to do this."; \
		exit 1; \
	fi

.PHONY: check-is-chroot
check-is-chroot: check-root
	@if [ ! -d /workspace ]; then \
		echo "You are not inside chroot environment."; \
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
	@echo "[`date +'%F %T'`] Getting sources for ports"
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
	@echo 'export CFLAGS="$(CFLAGS)"' > $(PKGMK_CONFIG_FILE)
	@echo 'export CXXFLAGS="$(CFLAGS)"' >> $(PKGMK_CONFIG_FILE)
	@echo 'export MAKEFLAGS="-j$(shell nproc)"' >> $(PKGMK_CONFIG_FILE)
	@echo 'PKGMK_COMPRESSION_MODE="$(PKGMK_COMPRESSION_MODE)"' >> $(PKGMK_CONFIG_FILE)
	@echo 'PKGMK_DOWNLOAD_PROG="curl"' >> $(PKGMK_CONFIG_FILE)
	@echo 'PKGMK_CURL_OPTS="--silent --retry 3"' >> $(PKGMK_CONFIG_FILE)

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
	@echo "[`date +'%F %T'`] Preparing $(PORTS_STAGE0_FILE)"
	@prt-get --config=$(PRTGET_CONFIG_FILE) quickdep $(PORTS_STAGE0) > $(PORTS_STAGE0_FILE)
$(PORTS_STAGE0_FILE): prepare-stage0-file

.PHONY: clean-stage0-file
clean-stage0-file: $(PORTS_STAGE0_FILE)
	@rm -f $(PORTS_STAGE0_FILE)

# Generates ports.stage1 (list of ports required to create the stage1)
.PHONY: prepare-stage1-file
prepare-stage1-file: $(PORTS_DIR) $(PRTGET_CONFIG_FILE)
	@echo "[`date +'%F %T'`] Preparing $(PORTS_STAGE1_FILE)"
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

# Build all ports in stage0
.PHONY: build-stage0
build-stage0: check-optimization $(PKGMK_CONFIG_FILE) $(PRTGET_CONFIG_FILE)
	@for PORT in `cat $(PORTS_STAGE0_FILE)`; do \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		echo "[`date +'%F %T'`] Building port: $$portdir" ; \
		( cd $$portdir && $(PKGMK_CMD) -d -cf $(PKGMK_CONFIG_FILE) $(PKGMK_CMD_OPTS) ); \
	done

# Build all ports in stage1. Since ports are built in dependency order,
# after each port is built, it is installed.
# CAVEAT: This target must be run within the chroot environment as it installs
# packages and could be a serious problem if run outside of the jail.
.PHONY: build-stage1
build-stage1: check-is-chroot check-optimization $(PKGMK_CONFIG_FILE) $(PRTGET_CONFIG_FILE)
	@for PORT in `cat $(PORTS_STAGE1_FILE)`; do \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		echo "[`date +'%F %T'`] Building port: $$portdir" ; \
		cd $$portdir && \
			$(PKGMK_CMD) -d -cf $(PKGMK_CONFIG_FILE) $(PKGMK_CMD_OPTS) && \
			prt-get --config=$(PRTGET_CONFIG_FILE) install $$PORT || prt-get --config=$(PRTGET_CONFIG_FILE) update $$PORT; \
	done

#------------------------------------------------------------------------------
# STAGE0
#
# Build toolchain ports
#
.PHONY: stage0
stage0: $(PORTS_STAGE0_FILE)
	$(MAKE) build-stage0 PKGMK_FAKEROOT=yes

#------------------------------------------------------------------------------
# STAGE1
#
# - Download sources for all ports in stage1 (to avoid use wget/curl inside the chroot)
#   On stage0, ports are compiled and linked against the host. So stage0 packages may have broken dependencies
#   and may fail when running inside a chroot environment.
#
# - Create rootfs with packages built in stage0
#
# - Chroot into rootfs and build/install all of them in dependency order
#
.PHONY: stage1
stage1: $(PORTS_STAGE0_FILE) $(PORTS_STAGE1_FILE) $(PKGMK_CONFIG_FILE) $(PRTGET_CONFIG_FILE)
	@echo "[`date +'%F %T'`] Backup packages from stage0"
	@cd $(PORTS_DIR) && \
		tar cf $(WORKSPACE_DIR)packages.stage0.tar `find . -type f -name "*.pkg.tar.$(PKGMK_COMPRESSION_MODE)"`
	@echo "[`date +'%F %T'`] Download port sources"
	@for PORT in `cat $(PORTS_STAGE1_FILE)`; do \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		echo "[`date +'%F %T'`] - port: $$portdir" ; \
		( cd $$portdir && $(PKGMK_CMD) -do -cf $(PKGMK_CONFIG_FILE)); \
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
	@sudo mkdir $(ROOTFS_DIR)/workspace
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
	@sudo mount --bind $(WORKSPACE_DIR) $(ROOTFS_DIR)/workspace
	@echo "[`date +'%F %T'`] Entering chroot enrivonment"
	@PORTS="`cat $(PORTS_STAGE1_FILE)`"
	@sudo chroot $(ROOTFS_DIR) /bin/bash --login -c \
		"cd /workspace && $(MAKE) build-stage1 PKGMK_FORCE=yes" || exit 0
	@echo "[`date +'%F %T'`] Exiting chroot enrivonment"
	@echo "[`date +'%F %T'`] - Unmounting $(ROOTFS_DIR)/workspace"
	@sudo umount $(ROOTFS_DIR)/workspace
	@echo "[`date +'%F %T'`] - Unmounting $(ROOTFS_DIR)/proc"
	@sudo umount $(ROOTFS_DIR)/proc
	@echo "[`date +'%F %T'`] - Unmounting $(ROOTFS_DIR)/dev"
	@sudo umount $(ROOTFS_DIR)/dev

.PHONY: bootstrap
bootstrap:
	@echo "[`date +'%F %T'`] Bootstrap started"
	@echo "[`date +'%F %T'`] - Stage 0"
	$(MAKE) stage0 2>&1 | tee stage0.log
	@grep -e 'failed\.' -e 'succeeded\.' stage0.log
	@echo "[`date +'%F %T'`] - Stage 1"
	$(MAKE) stage1 2>&1 | tee stage1.log
	@grep -e 'failed\.' -e 'succeeded\.' stage1.log
	@echo "[`date +'%F %T'`] Bootstrap completed"

# TODO: improve and add feature: upload to mirror
.PHONY: release
release: $(ROOTFS_DIR)
	@echo "[`date +'%F %T'`] Cleaning up"
	@test ! -d $(ROOTFS_DIR)/workspace || \
		sudo rmdir $(ROOTFS_DIR)/workspace
	@sudo rm -f $(ROOTFS_DIR)/etc/pkgmk.conf && \
		sudo cp $(PORTS_DIR)/core-arm/pkgutils/pkgmk.conf $(ROOTFS_DIR)/etc/pkgmk.conf
	@sudo rm -f $(ROOTFS_DIR)/etc/prt-get.conf && \
		sudo cp $(PORTS_DIR)/core-arm/prt-get/prt-get.conf $(ROOTFS_DIR)/etc/prt-get.conf
	@echo "[`date +'%F %T'`] Building crux-arm-$(CRUX_ARM_VERSION).rootfs.tar.xz"
	@cd $(ROOTFS_DIR) && \
		sudo tar cJf ../crux-arm-$(CRUX_ARM_VERSION).rootfs.tar.xz *
	@echo "[`date +'%F %T'`] Release completed"

# TODO: improve and add feature: upload to mirror
.PHONY: release-packages
release-packages: $(PORTS)
	@find $(PORTS) -type f -name '*.pkg.tar.$(PKGMK_COMPRESSION_MODE)'
