#
# Description: Build CRUX-ARM releases
#
# The first objective for this script is to generate a generic release (i.e: crux-arm-3.7.rootfs.tar.xz)
# But also it will run from ARM compatible devices to generate optimized releases (i.e: crux-arm-3.7.rootfs.odroidxu4.tar.xz)

CRUX_ARM_VERSION = 3.7
CRUX_ARM_GIT_PREFIX = https://github.com/crux-arm
CRUX_GIT_PREFIX = git://crux.nu/ports
CRUX_GIT_HASH = 2f90d87a2cc97cb07fc7d6226f5d9fce219bcc0f

# This is the top dir where Makefile lives
# We should use this with care, because it could harcode absolute paths in files
# An example of this hardcode may appear for each prtdir in prt-get.conf
ifndef WORKSPACE_DIR
WORKSPACE_DIR = $(realpath $(dir $(abspath $(firstword $(MAKEFILE_LIST)))))
endif

CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)

PORTS_DIR = $(WORKSPACE_DIR)/ports

PORTS_STAGE0_FILE = $(WORKSPACE_DIR)/ports.stage0
PORTS_STAGE1_FILE = $(WORKSPACE_DIR)/ports.stage1

# This file exists to make possible continue building stage1 ports from a selected point
PORTS_STAGE1_PENDING_FILE = $(WORKSPACE_DIR)/pending.stage1

# stage0 ports are the minimal base for creating a chroot where continue building ports
PORTS_STAGE0 = automake attr bash binutils bison coreutils dash diffutils file \
	filesystem findutils gawk gettext gcc grep glibc gperf gzip libtool m4 make \
	patch perl pkgconf pkgutils prt-get python3 sed tar util-linux

# ports that will not take part in the release
PORTS_BLACKLIST = glibc-32 jsoncpp libuv lzlib rhash

PKGMK_CONFIG_FILE = $(WORKSPACE_DIR)/pkgmk.conf
PKGMK_COMPRESSION_MODE = xz
PRTGET_CONFIG_FILE = $(WORKSPACE_DIR)/prt-get.conf

PACKAGES_STAGE0_TAR_FILE = $(WORKSPACE_DIR)/packages.stage0.tar.xz
PACKAGES_STAGE1_TAR_FILE = $(WORKSPACE_DIR)/packages.stage1.tar.xz

ROOTFS_STAGE0_DIR = $(WORKSPACE_DIR)/rootfs-stage0
ROOTFS_STAGE1_DIR = $(WORKSPACE_DIR)/rootfs-stage1

ROOTFS_TAR_FILE = $(WORKSPACE_DIR)/rootfs.tar.xz
ROOTFS_STAGE0_TAR_FILE = $(WORKSPACE_DIR)/rootfs.stage0.tar.xz
ROOTFS_STAGE1_TAR_FILE = $(WORKSPACE_DIR)/rootfs.stage1.tar.xz

RELEASE_TAR_FILE = crux-arm-$(CRUX_ARM_VERSION).rootfs.tar.xz

# Optimization based on devices
ifndef DEVICE_OPTIMIZATION
DEVICE_OPTIMIZATION = arm
endif
# Load CFLAGS and COLLECTIONS for selected optimization
include $(WORKSPACE_DIR)/devices/$(DEVICE_OPTIMIZATION).mk

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
	@if [ "$(CURRENT_UID)" != "0" ]; then \
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
# Upstream ports from CRUX's core is frozen to a certain version: $(CRUX_GIT_HASH)
.PHONY: prepare-ports-dir
prepare-ports-dir: $(PORTS_DIR)
$(PORTS_DIR):
	@echo "[`date +'%F %T'`] Getting sources for ports"
	@for COLL in $(COLLECTIONS); do \
		if [ ! -d $(PORTS_DIR)/$$COLL ]; then \
			case $$COLL in \
				core) \
					git clone -b $(CRUX_ARM_VERSION) --single-branch $(CRUX_GIT_PREFIX)/$$COLL $(PORTS_DIR)/$$COLL ; \
					cd $(PORTS_DIR)/$$COLL && git reset --hard $(CRUX_GIT_HASH) ;; \
				*-arm|*-arm64) \
					git clone -b $(CRUX_ARM_VERSION) --single-branch $(CRUX_ARM_GIT_PREFIX)/crux-ports-$$COLL $(PORTS_DIR)/$$COLL ;; \
			esac \
		fi \
	done

# Generates pkgmk.conf
.PHONY: prepare-pkgmkconf
prepare-pkgmkconf: $(PKGMK_CONFIG_FILE)
$(PKGMK_CONFIG_FILE):
	@echo 'export CFLAGS="$(CFLAGS)"' > $(PKGMK_CONFIG_FILE)
	@echo 'export CXXFLAGS="$(CFLAGS)"' >> $(PKGMK_CONFIG_FILE)
	@echo 'export MAKEFLAGS="-j$(shell nproc)"' >> $(PKGMK_CONFIG_FILE)
	@echo 'PKGMK_COMPRESSION_MODE="$(PKGMK_COMPRESSION_MODE)"' >> $(PKGMK_CONFIG_FILE)
	@echo 'PKGMK_DOWNLOAD_PROG="curl"' >> $(PKGMK_CONFIG_FILE)
	@echo 'PKGMK_CURL_OPTS="--silent --retry 3"' >> $(PKGMK_CONFIG_FILE)

.PHONY: clean-pkgmkconf
clean-pkgmkconf: $(PKGMK_CONFIG_FILE)
	@rm -f $(PKGMK_CONFIG_FILE)

# Generates prt-get.conf
# NOTE: An absolute path is used for each prtdir, so it is convenient to regenerate
# this file once it is called from within the chroot on stage1.
.PHONY: prepare-prtgetconf
prepare-prtgetconf: $(PRTGET_CONFIG_FILE)
$(PRTGET_CONFIG_FILE): $(PORTS_DIR)
	@:> $(PRTGET_CONFIG_FILE)
	@for COLL in $(COLLECTIONS); do \
		echo "prtdir $(PORTS_DIR)/$$COLL" >> $(PRTGET_CONFIG_FILE); \
	done
	@echo "rmlog_on_success no" >> $(PRTGET_CONFIG_FILE)
	@echo "runscripts yes" >> $(PRTGET_CONFIG_FILE)

.PHONY: clean-prtgetconf
clean-prtgetconf: $(PRTGET_CONFIG_FILE)
	@rm -f $(PRTGET_CONFIG_FILE)

# Generates ports.stage0 (list of ports required to create the stage0)
.PHONY: prepare-stage0-file
prepare-stage0-file: $(PORTS_STAGE0_FILE)
$(PORTS_STAGE0_FILE): $(PORTS_DIR) $(PRTGET_CONFIG_FILE)
	@echo "[`date +'%F %T'`] Preparing $(PORTS_STAGE0_FILE)"
	@prt-get --config=$(PRTGET_CONFIG_FILE) quickdep $(PORTS_STAGE0) > $(PORTS_STAGE0_FILE)

.PHONY: clean-stage0-file
clean-stage0-file: $(PORTS_STAGE0_FILE)
	@rm -f $(PORTS_STAGE0_FILE)

# Generates ports.stage1 (list of ports required to create the stage1)
.PHONY: prepare-stage1-file
prepare-stage1-file: $(PORTS_STAGE1_FILE)
$(PORTS_STAGE1_FILE): $(PORTS_DIR) $(PRTGET_CONFIG_FILE)
	@echo "[`date +'%F %T'`] Preparing $(PORTS_STAGE1_FILE)"
	@prt-get --config=$(PRTGET_CONFIG_FILE) list > $(PORTS_STAGE1_FILE).tmp
	@for bl in $(PORTS_BLACKLIST); do \
		sed "/^$$bl/d" -i $(PORTS_STAGE1_FILE).tmp; \
	done
	@prt-get --config=$(PRTGET_CONFIG_FILE) quickdep `cat $(PORTS_STAGE1_FILE).tmp | tr '\n' ' '` > $(PORTS_STAGE1_FILE)
	@rm -f $(PORTS_STAGE1_FILE).tmp

.PHONY: clean-stage1-file
clean-stage1-file: $(PORTS_STAGE1_FILE)
	@rm -f $(PORTS_STAGE1_FILE)

# Build each port from PORTS_STAGE0_FILE.
# When all have been generated correctly, a tar.xz file is built with all the packages for backup purposes.
.PHONY: build-stage0-packages
build-stage0-packages: check-optimization $(PACKAGES_STAGE0_TAR_FILE)
$(PACKAGES_STAGE0_TAR_FILE): $(PORTS_DIR) $(PKGMK_CONFIG_FILE) $(PRTGET_CONFIG_FILE) $(PORTS_STAGE0_FILE)
	@echo "[`date +'%F %T'`] Building stage0 packages from $(PORTS_STAGE0_FILE)"
	@for PORT in `cat $(PORTS_STAGE0_FILE)`; do \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		echo "[`date +'%F %T'`] Building port: $$portdir" ; \
		( cd $$portdir && $(PKGMK_CMD) -d -cf $(PKGMK_CONFIG_FILE) $(PKGMK_CMD_OPTS) ) || exit 1; \
	done
	@echo "[`date +'%F %T'`] Creating $(PACKAGES_STAGE0_TAR_FILE)"
	@tar caf $(PACKAGES_STAGE0_TAR_FILE) `find ports -type f -name "*.pkg.tar.$(PKGMK_COMPRESSION_MODE)"`

# Create a rootfs with stage0 packages
.PHONY: build-stage0-rootfs
build-stage0-rootfs: $(ROOTFS_STAGE0_TAR_FILE)
$(ROOTFS_STAGE0_TAR_FILE): $(PACKAGES_STAGE0_TAR_FILE) $(PRTGET_CONFIG_FILE) $(PORTS_STAGE0_FILE)
	@echo "[`date +'%F %T'`] Creating rootfs from stage0 packages in $(ROOTFS_STAGE0_DIR)"
	@sudo mkdir $(ROOTFS_STAGE0_DIR) || exit 1
	@sudo mkdir -p $(ROOTFS_STAGE0_DIR)/var/lib/pkg
	@sudo touch $(ROOTFS_STAGE0_DIR)/var/lib/pkg/db
	@for PORT in `cat $(PORTS_STAGE0_FILE)`; do \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		package=`find $$portdir -type f -name "$$PORT#*.$(PKGMK_COMPRESSION_MODE)"`; \
		echo "[`date +'%F %T'`] - package: $$package"; \
		sudo pkgadd -r $(ROOTFS_STAGE0_DIR) $$package || exit 1; \
	done
	@echo "[`date +'%F %T'`] Installing extras"
	@sudo cp -L /etc/resolv.conf $(ROOTFS_STAGE0_DIR)/etc/resolv.conf
	@sudo mkdir $(ROOTFS_STAGE0_DIR)/workspace
	@sudo ln -sf /workspace/pkgmk.conf $(ROOTFS_STAGE0_DIR)/etc/pkgmk.conf
	@sudo ln -sf /workspace/prt-get.conf $(ROOTFS_STAGE0_DIR)/etc/prt-get.conf
	@echo "[`date +'%F %T'`] Installing hacks to avoid host dependencies"
	@sudo ln -sf libnsl.so.3 $(ROOTFS_STAGE0_DIR)/usr/lib/libnsl.so.2
	@echo "[`date +'%F %T'`] Creating $(ROOTFS_STAGE0_TAR_FILE)"
	@cd $(ROOTFS_STAGE0_DIR) && sudo tar caf $(ROOTFS_STAGE0_TAR_FILE) *
	@sudo chown $(CURRENT_UID):$(CURRENT_GID) $(ROOTFS_STAGE0_TAR_FILE)
	@sudo rm -rf $(ROOTFS_STAGE0_DIR)

# Setup a valid rootfs to chroot with the content of rootfs.tar.xz
# This is automated on target bootstrap and could be useful also in other scenarios:
# - Start building (in case of failure) a fresh stage1 using. Steps:
#     $ ln -s stage0.rootfs.tar.xz rootfs.tar.xz
#     $ make stage1
# - Build optimizations for devices using the generic release. Steps:
#     $ ln -s crux-arm-3.7.rootfs.tar.xz rootfs.tar.xz
#     $ make stage1 DEVICE_OPTIMIZATION=foo
.PHONY: prepare-stage1-rootfs
prepare-stage1-rootfs: $(ROOTFS_STAGE1_DIR)
$(ROOTFS_STAGE1_DIR): $(ROOTFS_TAR_FILE) $(PKGMK_CONFIG_FILE) $(PRTGET_CONFIG_FILE)
	@echo "[`date +'%F %T'`] Creating $(ROOTFS_STAGE1_DIR)"
	@sudo mkdir $(ROOTFS_STAGE1_DIR) || exit 1
	@echo "[`date +'%F %T'`] Decompressing $(ROOTFS_TAR_FILE) to $(ROOTFS_STAGE1_DIR)"
	@sudo tar -C $(ROOTFS_STAGE1_DIR) -xf $(ROOTFS_TAR_FILE)
	@echo "[`date +'%F %T'`] Installing extras"
	@sudo cp -L /etc/resolv.conf $(ROOTFS_STAGE1_DIR)/etc/resolv.conf
	@test -d $(ROOTFS_STAGE1_DIR)/workspace || sudo mkdir $(ROOTFS_STAGE1_DIR)/workspace
	@sudo ln -sf /workspace/pkgmk.conf $(ROOTFS_STAGE1_DIR)/etc/pkgmk.conf
	@sudo ln -sf /workspace/prt-get.conf $(ROOTFS_STAGE1_DIR)/etc/prt-get.conf


.PHONY: download-stage1-sources
download-stage1-sources: $(PKGMK_CONFIG_FILE) $(PRTGET_CONFIG_FILE) $(PORTS_STAGE1_FILE)
	@echo "[`date +'%F %T'`] Downloading port sources"
	@for PORT in `cat $(PORTS_STAGE1_FILE)`; do \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		echo "[`date +'%F %T'`] - port: $$portdir" ; \
		( cd $$portdir && $(PKGMK_CMD) -do -cf $(PKGMK_CONFIG_FILE)) || exit 1; \
	done


# Build all ports in stage1.
# Since ports are built in dependency order, after each port is built, it is installed.
# CAVEAT: This target must be run within the chroot environment as it installs packages
# and could be a serious problem if run outside of the jail.
.PHONY: build-stage1-packages
build-stage1-packages: check-is-chroot check-optimization $(PACKAGES_STAGE1_TAR_FILE)
$(PACKAGES_STAGE1_TAR_FILE): $(PORTS_DIR) $(PKGMK_CONFIG_FILE) $(PRTGET_CONFIG_FILE) $(PORTS_STAGE1_FILE)
	@test -f $(PORTS_STAGE1_PENDING_FILE) || cp $(PORTS_STAGE1_FILE) $(PORTS_STAGE1_PENDING_FILE)
	@for PORT in `cat $(PORTS_STAGE1_FILE)`; do \
		sed 's| |\n|g' $(PORTS_STAGE1_PENDING_FILE) | grep ^$$PORT$$ || continue; \
		portdir=`prt-get --config=$(PRTGET_CONFIG_FILE) path "$$PORT"`; \
		echo "[`date +'%F %T'`] Building port: $$portdir" ; \
		( cd $$portdir && $(PKGMK_CMD) -d -cf $(PKGMK_CONFIG_FILE) $(PKGMK_CMD_OPTS) ) || exit 1; \
		prt-get --config=$(PRTGET_CONFIG_FILE) install $$PORT || prt-get --config=$(PRTGET_CONFIG_FILE) update $$PORT; \
		sed 's| |\n|g' $(PORTS_STAGE1_PENDING_FILE) | grep -v ^$$PORT$$ | tr '\n' ' ' > $(PORTS_STAGE1_PENDING_FILE).tmp && \
			mv $(PORTS_STAGE1_PENDING_FILE).tmp  $(PORTS_STAGE1_PENDING_FILE); \
	done
	@echo "[`date +'%F %T'`] Creating $(PACKAGES_STAGE1_TAR_FILE)"
	@tar caf $(PACKAGES_STAGE1_TAR_FILE) `find ports -type f -name "*.pkg.tar.$(PKGMK_COMPRESSION_MODE)"`

#------------------------------------------------------------------------------
# STAGE0
#
#
.PHONY: stage0
stage0:
	$(MAKE) build-stage0-packages PKGMK_FAKEROOT=yes
	$(MAKE) build-stage0-rootfs

#------------------------------------------------------------------------------
# STAGE1
#
#
.PHONY: stage1
stage1:
	@echo "[`date +'%F %T'`] Preparing chroot environment ($(ROOTFS_STAGE1_DIR))"
	$(MAKE) prepare-stage1-rootfs
	$(MAKE) download-stage1-sources
	@echo "[`date +'%F %T'`] Cleaning up before entering into chroot environment"
	$(MAKE) clean-prtgetconf
	@echo "[`date +'%F %T'`] Mounting /dev on $(ROOTFS_STAGE1_DIR)/dev"
	@mountpoint -q $(ROOTFS_STAGE1_DIR)/dev || sudo mount --bind /dev $(ROOTFS_STAGE1_DIR)/dev
	@echo "[`date +'%F %T'`] Mounting /proc on $(ROOTFS_STAGE1_DIR)/proc"
	@mountpoint -q $(ROOTFS_STAGE1_DIR)/proc || sudo mount --bind /proc $(ROOTFS_STAGE1_DIR)/proc
	@echo "[`date +'%F %T'`] Mounting $(WORKSPACE_DIR) on $(ROOTFS_STAGE1_DIR)/workspace"
	@mountpoint -q $(ROOTFS_STAGE1_DIR)/workspace || sudo mount --bind $(WORKSPACE_DIR) $(ROOTFS_STAGE1_DIR)/workspace
	@echo "[`date +'%F %T'`] Entering chroot enrivonment"
	@sudo chroot $(ROOTFS_STAGE1_DIR) /bin/bash --login -c \
		"cd /workspace && $(MAKE) build-stage1-packages PKGMK_FORCE=yes WORKSPACE_DIR=/workspace || exit 0"
	@echo "[`date +'%F %T'`] Exiting chroot enrivonment"
	@echo "[`date +'%F %T'`] Unmounting $(ROOTFS_STAGE1_DIR)/workspace"
	@sudo umount -f $(ROOTFS_STAGE1_DIR)/workspace
	@echo "[`date +'%F %T'`] Unmounting $(ROOTFS_STAGE1_DIR)/proc"
	@sudo umount -f $(ROOTFS_STAGE1_DIR)/proc
	@echo "[`date +'%F %T'`] Unmounting $(ROOTFS_STAGE1_DIR)/dev"
	@sudo umount -f $(ROOTFS_STAGE1_DIR)/dev

#------------------------------------------------------------------------------
# BOOSTRAP
#
#
.PHONY: bootstrap
bootstrap:
	@echo "[`date +'%F %T'`] Bootstrap started"
	@echo "[`date +'%F %T'`] Running Stage 0"
	$(MAKE) stage0 2>&1 | tee stage0.log
	@grep -e 'failed\.' -e 'succeeded\.' stage0.log
	@echo "[`date +'%F %T'`] Selecting $(ROOTFS_TAR_FILE) -> $(ROOTFS_STAGE0_TAR_FILE)"
	@ln -s $(ROOTFS_STAGE0_TAR_FILE) $(ROOTFS_TAR_FILE)
	@echo "[`date +'%F %T'`] Running Stage 1"
	$(MAKE) stage1 2>&1 | tee stage1.log
	@grep -e 'failed\.' -e 'succeeded\.' stage1.log
	@echo "[`date +'%F %T'`] Bootstrap completed"

#------------------------------------------------------------------------------
# RELEASE
#
#
.PHONY: release
release: $(RELEASE_TAR_FILE)
$(ROOTFS_STAGE1_TAR_FILE): $(ROOTFS_STAGE1_DIR)
	@echo "[`date +'%F %T'`] Cleaning up"
	@test ! -d $(ROOTFS_STAGE1_DIR)/workspace || sudo rmdir $(ROOTFS_STAGE1_DIR)/workspace
	@sudo rm -f $(ROOTFS_STAGE1_DIR)/etc/pkgmk.conf
	@sudo rm -f $(ROOTFS_STAGE1_DIR)/etc/prt-get.conf
	@sudo rm -rf $(ROOTFS_STAGE1_DIR)/var/lib/pkg/rejected/*
	@echo "[`date +'%F %T'`] Copying config files"
	@sudo cp $(PORTS_DIR)/$(word 1, $(COLLECTIONS))/pkgutils/pkgmk.conf $(ROOTFS_STAGE1_DIR)/etc/pkgmk.conf
	@sudo cp $(PORTS_DIR)/$(word 1, $(COLLECTIONS))/prt-get/prt-get.conf $(ROOTFS_STAGE1_DIR)/etc/prt-get.conf
	@echo "[`date +'%F %T'`] Building $(ROOTFS_STAGE1_TAR_FILE)"
	@cd $(ROOTFS_STAGE1_DIR) && \
		sudo tar cJf $(ROOTFS_STAGE1_TAR_FILE) * && \
		sudo chown $(CURRENT_UID):$(CURRENT_GID) $(ROOTFS_STAGE1_TAR_FILE)
$(RELEASE_TAR_FILE): $(ROOTFS_STAGE1_TAR_FILE)
	@echo "[`date +'%F %T'`] Using the final name $(RELEASE_TAR_FILE)"
	@cd $(WORKSPACE_DIR) && ln -s $(ROOTFS_STAGE1_TAR_FILE) $(RELEASE_TAR_FILE)
	@echo "[`date +'%F %T'`] Release completed"
