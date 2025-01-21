# Makefile for CRUX-ARM Release
# Automates the build and packaging process for CRUX-ARM root filesystems
#
# Copyright (C) 2025 CRUX-ARM System Team <devel AT crux-arm DOT nu>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# Usage:
#   make stage0     - Build base packages (Stage 0)
#   make stage1     - Build additional packages in chroot (Stage 1)
#   make release    - Create final CRUX-ARM release package
#   make bootstrap  - Run the full build process
#
# For more information, run:
#   make help

# Colorized output
NO_COLORS ?= 0
ifeq ($(NO_COLORS),0)
COLOR_RESET   = \033[0m
COLOR_BOLD    = \033[1m
COLOR_BLUE   = \033[1;34m
COLOR_RED     = \033[31m
COLOR_YELLOW = \033[0;33m
endif

# Print debug lines
DEBUG = @echo "$(COLOR_BOLD)$(COLOR_YELLOW)[$$(date +'%F %T')]$(COLOR_RESET)$(COLOR_BOLD)$(COLOR_BLUE)$(1)$(COLOR_RESET)"

# CRUX-ARM architecture variant
CRUX_ARM_ARCH = arm64

# Overlay ports from CRUX-ARM repositories
CRUX_ARM_VERSION = 3.8
CRUX_ARM_GIT_PREFIX = https://github.com/crux-arm
#CRUX_ARM_GIT_HASH =

# Upstream ports from CRUX repositories
CRUX_VERSION = 3.8
CRUX_GIT_PREFIX = https://git.crux.nu/ports
#CRUX_GIT_HASH = 90440d8a8a

CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)

# This is the top dir where Makefile lives
# We should use this with care, because it changes from stage0 to stage1 and
# could harcode absolute paths in files
# An example of this hardcode may appear for dirs in pkgmk.conf or in prt-get.conf
WORKSPACE_DIR ?= $(realpath $(dir $(abspath $(firstword $(MAKEFILE_LIST)))))

# Common directories to all stages
PORTS_DIR = $(WORKSPACE_DIR)/ports
SOURCES_DIR = $(WORKSPACE_DIR)/sources

STAGE0_WORK_DIR = $(WORKSPACE_DIR)/stage0
STAGE1_WORK_DIR = $(WORKSPACE_DIR)/stage1

STAGE0_PORTS_FILE = $(STAGE0_WORK_DIR)/ports.list
STAGE1_PORTS_FILE = $(STAGE1_WORK_DIR)/ports.list

# This file exists to make possible continue building stage1 ports from a selected point
STAGE1_PORTS_FILE_INDEX = $(STAGE1_WORK_DIR)/ports.list.index

# List of ports that must form a valid minimal rootfs. The dependencies of the ports
# should not be included here; they will be calculated in the stage0-ports-file."
## Added curl and friends to be able to rebuild ports in stage1 - take it as a quirk
## Also added meson ninja rsync to be able to successfully build stage1
BASE_PORTS = automake attr bash binutils bison coreutils dash diffutils file \
	filesystem findutils gawk gettext gcc grep glibc gperf gzip libtool m4 make \
	openssl patch perl pkgconf pkgutils prt-get python3 sed tar util-linux \
	curl ca-certificates \
	meson ninja rsync

# This is a list of ports that are build-time dependencies of other ports but are not
# listed as such, breaking the dependency sequence calculated in prepare-stage1-ports-file
# As a result, they should be installed before the rest of the ports in stage1
BUILDTIME_PORTS = python3-setuptools ninja meson libuv lzlib rhash jsoncpp \
	ca-certificates libnghttp2 openssl curl cmake

# List of ports which will not be part of either the stage0 rootfs or the release.
# If one of these ports appears in the ports.list file in stage1 or stage2, it is
# because it is included as a dependency of another port.
PORTS_BLACKLIST = glibc-32 jsoncpp libuv lzlib rhash libcap libcap-ng libxcrypt-32

STAGE0_PKGMK_CONFIG_FILE = $(STAGE0_WORK_DIR)/pkgmk.conf
STAGE1_PKGMK_CONFIG_FILE = $(STAGE1_WORK_DIR)/pkgmk.conf

STAGE0_PRTGET_CONFIG_FILE = $(STAGE0_WORK_DIR)/prt-get.conf
STAGE1_PRTGET_CONFIG_FILE = $(STAGE1_WORK_DIR)/prt-get.conf

STAGE0_PACKAGES_DIR = $(STAGE0_WORK_DIR)/packages
STAGE1_PACKAGES_DIR = $(STAGE1_WORK_DIR)/packages

STAGE0_PACKAGES_DONE_FILE = $(STAGE0_WORK_DIR)/packages.done
STAGE1_PACKAGES_DONE_FILE = $(STAGE1_WORK_DIR)/packages.done

STAGE0_ROOTFS_DIR = $(WORKSPACE_DIR)/rootfs-stage0
STAGE1_ROOTFS_DIR = $(WORKSPACE_DIR)/rootfs-stage1

STAGE0_ROOTFS_TAR_FILE = $(STAGE0_WORK_DIR)/crux-arm-$(RELEASE_VERSION).rootfs-stage0.tar.xz
STAGE1_ROOTFS_TAR_FILE = $(STAGE1_WORK_DIR)/crux-arm-$(RELEASE_VERSION).rootfs-stage1.tar.xz

STAGE0_LOG_FILE = $(STAGE0_WORK_DIR)/stage0.log
STAGE1_LOG_FILE = $(STAGE1_WORK_DIR)/stage1.log

# Optimization based on devices
DEVICE_OPTIMIZATION ?= $(CRUX_ARM_ARCH)

# Release version examples (EDIT AS NEEDED)
#   3.8-arm64
#   3.8-rc4-armhf
#   3.8-dev2-raspberrypi4
# The strategy to follow is to start with dev1, dev2, etc., until CRUX upstream freezes ports for rc1.
# At that point, we will begin using rc1, rc2, ... following CRUX and continuing up to rcN when we
# confirm a release is ready
RELEASE_VERSION ?= $(CRUX_ARM_VERSION)-dev1-$(DEVICE_OPTIMIZATION)
RELEASE_TAR_FILE = $(WORK_DIR)/crux-arm-$(RELEASE_VERSION).rootfs.tar.xz

# Load CFLAGS and COLLECTIONS for selected optimization
ifneq ("$(wildcard $(WORKSPACE_DIR)/devices/$(DEVICE_OPTIMIZATION).mk)", "")
include $(WORKSPACE_DIR)/devices/$(DEVICE_OPTIMIZATION).mk
endif

# Default build commands
PKGMK_CMD = pkgmk
PRTGET_CMD = prt-get

# Use fakeroot command to build packages
ifeq ($(PKGMK_FAKEROOT),yes)
PKGMK_CMD = fakeroot pkgmk
endif

# Check if the command exists
ifeq (, $(shell command -v $(PKGMK_CMD)))
  $(error $(RED)Error: $(PKGMK_CMD) command not found. $(RESET))
endif
# Check if the command exists
ifeq (, $(shell command -v $(PRTGET_CMD)))
  $(error $(RED)Error: $(PRTGET_CMD) command not found. $(RESET))
endif

# Default pkgmk options
PKGMK_CMD_OPTS ?= -is -im
# Append user defined options (e.g. -kw)
PKGMK_CMD_OPTS += $(PKGMK_CMD_EXTRA_OPTS)
# Other vars useful to create pkgmk.conf
PKGMK_SOURCE_DIR  ?= $(WORKSPACE_DIR)/sources
PKGMK_WORK_DIR ?= $(WORKSPACE_DIR)/work
PKGMK_COMPRESSION_MODE ?= xz

# Export environment variables
export CRUX_ARM_ARCH
export DEVICE_OPTIMIZATION
export RELEASE_VERSION
export WORKSPACE_DIR
export PKGMK_SOURCE_DIR
export PKGMK_WORK_DIR

.PHONY: help
help:
	@echo "Targets:"
	@echo '  help		Show this help information'
	@echo '  stage0	Build stage0 packages and rootfs'
	@echo '  stage1	Build stage1 packages and rootfs'
	@echo '  release	Build CRUX-ARM release'
	@echo '  bootstrap	Build all stages and bootstrap the release'
	@echo
	@echo 'Additional variables to all targets:'
	@echo
	@echo '  DEVICE_OPTIMIZATION	Optimize for an device (e.g: DEVICE_OPTIMIZATION=odroidxu4)'
	@echo '  NO_COLORS		Disable output color messages (e.g: NO_COLORS=1)'

.PHONY: clean
clean: clean-stage0 clean-stage1

.PHONY: debug
debug:
	$(call DEBUG, Debugging Environment variables)
	@env | grep \
		-e ^CRUX_ARM_ARCH \
		-e ^DEVICE_OPTIMIZATION \
		-e ^RELEASE_VERSION \
		-e ^WORKSPACE_DIR \
		-e ^PKGMK_SOURCE_DIR \
		-e ^PKGMK_WORK_DIR
	$(call DEBUG, Debugging Makefile variables)
	@echo "PORTS_DIR:            $(PORTS_DIR)"
	@echo "SOURCES_DIR:          $(SOURCES_DIR)"
	@echo "STAGE0_PACKAGES_DIR:  $(STAGE0_PACKAGES_DIR)"
	@echo "STAGE1_PACKAGES_DIR:  $(STAGE1_PACKAGES_DIR)"
	@echo "STAGE0_ROOTFS_DIR:    $(STAGE0_ROOTFS_DIR)"
	@echo "STAGE1_ROOTFS_DIR:    $(STAGE1_ROOTFS_DIR)"
	$(call DEBUG, Debugging stage0 pkgmk.conf)
	@cat $(STAGE0_PKGMK_CONFIG_FILE)
	$(call DEBUG, Debugging stage1 pkgmk.conf)
	@cat $(STAGE1_PKGMK_CONFIG_FILE)
	$(call DEBUG, Debugging stage0 prt-get.conf)
	@cat $(STAGE0_PRTGET_CONFIG_FILE)
	$(call DEBUG, Debugging stage1 prt-get.conf)
	@cat $(STAGE1_PRTGET_CONFIG_FILE)
	$(call DEBUG, Debugging stage0 ports.list)
	@cat $(STAGE0_PORTS_FILE)
	$(call DEBUG, Debugging stage1 ports.list)
	@cat $(STAGE1_PORTS_FILE)

# -----------------------------------------------------------------------------
# COMMON
#

# Clones all COLLECTIONS of ports required to generate the release
# Upstream ports from CRUX's core is frozen to a certain version: $(CRUX_GIT_HASH)
.PHONY: prepare-ports-dir
prepare-ports-dir: $(PORTS_DIR)/core $(PORTS_DIR)/core-$(CRUX_ARM_ARCH)
$(PORTS_DIR)/core:
$(PORTS_DIR)/core-$(CRUX_ARM_ARCH):
	$(call DEBUG, Getting sources for ports)
	@for COLL in $(COLLECTIONS); do \
		if [ ! -d $(PORTS_DIR)/$$COLL ]; then \
			case $$COLL in \
				core) \
					git clone -v -b $(CRUX_VERSION) \
						--single-branch $(CRUX_GIT_PREFIX)/$${COLL}.git $(PORTS_DIR)/$$COLL ; \
					if [ -z $(CRUX_GIT_HASH) ]; then \
						cd $(PORTS_DIR)/$$COLL && git reset --hard $(CRUX_GIT_HASH) ; \
					fi ;; \
				core-$(CRUX_ARM_ARCH)) \
					git clone -v -b $(CRUX_ARM_VERSION) \
						--single-branch $(CRUX_ARM_GIT_PREFIX)/crux-ports-$$COLL $(PORTS_DIR)/$$COLL ; \
					if [ -z $(CRUX_ARM_GIT_HASH) ]; then \
						cd $(PORTS_DIR)/$$COLL && git reset --hard $(CRUX_ARM_GIT_HASH) ; \
					fi ;; \
				*-$(CRUX_ARM_ARCH)) \
					git clone -v -b $(CRUX_ARM_VERSION) \
						--single-branch $(CRUX_ARM_GIT_PREFIX)/crux-ports-$$COLL $(PORTS_DIR)/$$COLL ;; \
			esac; \
			if [ ! -d $(PORTS_DIR)/$$COLL ]; then \
				echo "ERROR: git clone failed"; \
				exit 1; \
			fi \
		fi \
	done

# -----------------------------------------------------------------------------
# STAGE 0
#

.PHONY: prepare-stage0-work-dir
prepare-stage0-work-dir: $(STAGE0_WORK_DIR)
$(STAGE0_WORK_DIR):
	@mkdir -vp $(STAGE0_WORK_DIR)

# Generates pkgmk.conf
# NOTE: An absolute path is used for PKGMK_*_DIR, so it is convenient to regenerate
# this file on each stage.
.PHONY: prepare-stage0-pkgmkconf
prepare-stage0-pkgmkconf: $(STAGE0_PKGMK_CONFIG_FILE)
$(STAGE0_PKGMK_CONFIG_FILE): prepare-stage0-work-dir clean-stage0-pkgmkconf
	$(call DEBUG, Preparing file $(STAGE0_PKGMK_CONFIG_FILE))
	@echo 'export CFLAGS="$(CFLAGS)"' > $(STAGE0_PKGMK_CONFIG_FILE)
	@echo 'export CXXFLAGS="$(CFLAGS)"' >> $(STAGE0_PKGMK_CONFIG_FILE)
	@echo 'export MAKEFLAGS="-j$(shell nproc 2>/dev/null || echo 1)"' >> $(STAGE0_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_COMPRESSION_MODE="$(PKGMK_COMPRESSION_MODE)"' >> $(STAGE0_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_DOWNLOAD_PROG="curl"' >> $(STAGE0_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_CURL_OPTS="--silent --retry 3"' >> $(STAGE0_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_SOURCE_DIR="$(PKGMK_SOURCE_DIR)"' >> $(STAGE0_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_PACKAGE_DIR="$(STAGE0_PACKAGES_DIR)"' >> $(STAGE0_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_WORK_DIR="$(PKGMK_WORK_DIR)/$$name"' >> $(STAGE0_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_IGNORE_FOOTPRINT="yes"' >> $(STAGE0_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_IGNORE_SIGNATURE="yes"' >> $(STAGE0_PKGMK_CONFIG_FILE)
	@mkdir -vp $(PKGMK_WORK_DIR)

.PHONY: clean-stage0-pkgmkconf
clean-stage0-pkgmkconf:
	@rm -f $(STAGE0_PKGMK_CONFIG_FILE)

# Generates prt-get.conf
# NOTE: An absolute path is used for each prtdir, so it is convenient to regenerate
# this file on each stage.
.PHONY: prepare-stage0-prtgetconf
prepare-stage0-prtgetconf: $(STAGE0_PRTGET_CONFIG_FILE)
$(STAGE0_PRTGET_CONFIG_FILE): clean-stage0-prtgetconf $(PORTS_DIR)/core
	$(call DEBUG, Preparing file $(STAGE0_PRTGET_CONFIG_FILE) for collections $(COLLECTIONS))
	@for COLL in $(COLLECTIONS); do \
		echo "prtdir $(PORTS_DIR)/$$COLL" >> $(STAGE0_PRTGET_CONFIG_FILE); \
	done
	@echo "writelog enabled" >> $(STAGE0_PRTGET_CONFIG_FILE)
	@echo "logmode overwrite" >> $(STAGE0_PRTGET_CONFIG_FILE)
	@echo "rmlog_on_success no" >> $(STAGE0_PRTGET_CONFIG_FILE)
	@echo "logfile %n-%v-%r.prt-get.log" >> $(STAGE0_PRTGET_CONFIG_FILE)
	@echo "runscripts yes" >> $(STAGE0_PRTGET_CONFIG_FILE)

.PHONY: clean-stage0-prtgetconf
clean-stage0-prtgetconf:
	@rm -f $(STAGE0_PRTGET_CONFIG_FILE)

# Generates a list of ports required to create the stage0
.PHONY: prepare-stage0-ports-file
prepare-stage0-ports-file: $(STAGE0_PORTS_FILE)
$(STAGE0_PORTS_FILE): $(PORTS_DIR)/core $(PORTS_DIR)/core-$(CRUX_ARM_ARCH) clean-stage0-ports-file $(STAGE0_PRTGET_CONFIG_FILE)
	$(call DEBUG, Preparing file $(STAGE0_PORTS_FILE))
	@$(PRTGET_CMD) --config=$(STAGE0_PRTGET_CONFIG_FILE) quickdep $(BASE_PORTS) > $(STAGE0_PORTS_FILE)

.PHONY: clean-stage0-ports-file
clean-stage0-ports-file:
	@rm -f $(STAGE0_PORTS_FILE)

$(STAGE0_PACKAGES_DIR):
	@mkdir -vp $(STAGE0_PACKAGES_DIR)

# Build each port from STAGE0_PORTS_FILE
# Stores built packages in STAGE0_PACKAGES_DIR
# Creates a backup file STAGE0_PACKAGES_TAR_FILE with all packages
.PHONY: build-stage0-packages
build-stage0-packages: $(STAGE0_PACKAGES_DONE_FILE)
$(STAGE0_PACKAGES_DONE_FILE): $(STAGE0_PACKAGES_DIR) $(PORTS_DIR)/core $(PORTS_DIR)/core-$(CRUX_ARM_ARCH) $(STAGE0_PKGMK_CONFIG_FILE) $(STAGE0_PRTGET_CONFIG_FILE) $(STAGE0_PORTS_FILE)
	$(call DEBUG, Building stage0 packages from $(STAGE0_PORTS_FILE))
	@for PORT in `cat $(STAGE0_PORTS_FILE)`; do \
		portdir=`$(PRTGET_CMD) --config=$(STAGE0_PRTGET_CONFIG_FILE) path "$$PORT"`; \
		( cd $$portdir && $(PKGMK_CMD) -d -cf $(STAGE0_PKGMK_CONFIG_FILE) $(PKGMK_CMD_OPTS) ) || exit 1; \
	done
	@touch $(STAGE0_PACKAGES_DONE_FILE)

# Create a rootfs file with stage0 packages
.PHONY: build-stage0-rootfs-file
build-stage0-rootfs-file: $(STAGE0_ROOTFS_TAR_FILE)
$(STAGE0_ROOTFS_TAR_FILE): $(STAGE0_PACKAGES_DONE_FILE) $(STAGE0_PRTGET_CONFIG_FILE) $(STAGE0_PORTS_FILE)
	$(call DEBUG, Creating rootfs from stage0 packages: $(STAGE0_ROOTFS_DIR))
	@sudo mkdir -vp $(STAGE0_ROOTFS_DIR) || exit 1
	@sudo mkdir -vp $(STAGE0_ROOTFS_DIR)/var/lib/pkg
	@sudo touch $(STAGE0_ROOTFS_DIR)/var/lib/pkg/db
	@for PORT in `cat $(STAGE0_PORTS_FILE)`; do \
		portdir=`$(PRTGET_CMD) --config=$(STAGE0_PRTGET_CONFIG_FILE) path "$$PORT"`; \
		package_name=`grep '^name=' $$portdir/Pkgfile | sed 's/name=//'`; \
		package_version=`grep '^version=' $$portdir/Pkgfile | sed 's/version=//'`; \
		package_release=`grep '^release=' $$portdir/Pkgfile | sed 's/release=//'`; \
		package="$(STAGE0_PACKAGES_DIR)/$$package_name#$$package_version-$$package_release.pkg.tar.$(PKGMK_COMPRESSION_MODE)"; \
		echo "Installing $$package"; \
		sudo pkgadd -r $(STAGE0_ROOTFS_DIR) $$package || exit 1; \
	done
	$(call DEBUG, Installing extras)
	@sudo cp -vL /etc/resolv.conf $(STAGE0_ROOTFS_DIR)/etc/resolv.conf
	$(call DEBUG, Creating $(STAGE0_ROOTFS_TAR_FILE))
	@cd $(STAGE0_ROOTFS_DIR) && sudo tar cavf $(STAGE0_ROOTFS_TAR_FILE) *
	@sudo chown $(CURRENT_UID):$(CURRENT_GID) $(STAGE0_ROOTFS_TAR_FILE)

## TODO: first copy the version of the current Pkgfile and always use the latest?
.PHONY: fix-setuptools
fix-setuptools:
	$(call DEBUG, Copying ensurepip version of setuptools)
	cp setuptools.in $(PORTS_DIR)/core/python3-setuptools/Pkgfile

.PHONY: fix-perl
fix-perl:
	$(call DEBUG, Copying perl Pkgfile with fixed mandir)
	cp perl.in $(PORTS_DIR)/core/perl/Pkgfile

.PHONY: stage0
stage0:
	$(call DEBUG, Applying Pkgfile fixes)
	$(MAKE) -e fix-setuptools
	$(MAKE) -e fix-perl
	$(call DEBUG, Building Stage 0 packages)
	$(MAKE) -e build-stage0-packages PKGMK_FAKEROOT=yes
	$(call DEBUG, Building Stage 0 rootfs)
	$(MAKE) -e build-stage0-rootfs-file

.PHONY: clean-stage0
clean-stage0: clean-stage0-pkgmkconf clean-stage0-prtgetconf clean-stage0-ports-file
	@rm $(STAGE0_ROOTFS_TAR_FILE)

#------------------------------------------------------------------------------
# STAGE1
#

.PHONY: prepare-stage1-work-dir
prepare-stage1-work-dir: $(STAGE1_WORK_DIR)
$(STAGE1_WORK_DIR):
	@mkdir -vp $(STAGE1_WORK_DIR)

# Generates pkgmk.conf
# NOTE: An absolute path is used for PKGMK_*_DIR, so it is convenient to regenerate
# this file on each stage.
.PHONY: prepare-stage1-pkgmkconf
prepare-stage1-pkgmkconf: $(STAGE1_PKGMK_CONFIG_FILE)
$(STAGE1_PKGMK_CONFIG_FILE): prepare-stage1-work-dir clean-stage1-pkgmkconf
	$(call DEBUG, Preparing file $(STAGE1_PKGMK_CONFIG_FILE))
	@echo 'export CFLAGS="$(CFLAGS)"' > $(STAGE1_PKGMK_CONFIG_FILE)
	@echo 'export CXXFLAGS="$(CFLAGS)"' >> $(STAGE1_PKGMK_CONFIG_FILE)
	@echo 'export MAKEFLAGS="-j$(shell nproc 2>/dev/null || echo 1)"' >> $(STAGE1_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_COMPRESSION_MODE="$(PKGMK_COMPRESSION_MODE)"' >> $(STAGE1_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_DOWNLOAD_PROG="curl"' >> $(STAGE1_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_CURL_OPTS="--silent --retry 3"' >> $(STAGE1_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_SOURCE_DIR="$(PKGMK_SOURCE_DIR)"' >> $(STAGE1_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_PACKAGE_DIR="$(STAGE1_PACKAGES_DIR)"' >> $(STAGE1_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_WORK_DIR="$(PKGMK_WORK_DIR)/$$name"' >> $(STAGE1_PKGMK_CONFIG_FILE)
	@echo 'PKGMK_IGNORE_SIGNATURE="yes"' >> $(STAGE1_PKGMK_CONFIG_FILE)
	@mkdir -vp $(PKGMK_WORK_DIR)

.PHONY: clean-stage1-pkgmkconf
clean-stage1-pkgmkconf:
	@rm -f $(STAGE1_PKGMK_CONFIG_FILE)

# Generates prt-get.conf
# NOTE: An absolute path is used for each prtdir, so it is convenient to regenerate
# this file on each stage.
.PHONY: prepare-stage1-prtgetconf
prepare-stage1-prtgetconf: $(STAGE1_PRTGET_CONFIG_FILE)
$(STAGE1_PRTGET_CONFIG_FILE): clean-stage1-prtgetconf $(PORTS_DIR)/core $(PORTS_DIR)/core-$(CRUX_ARM_ARCH)
	$(call DEBUG, Preparing file $(STAGE1_PRTGET_CONFIG_FILE) for collections $(COLLECTIONS))
	@for COLL in $(COLLECTIONS); do \
		echo "prtdir $(PORTS_DIR)/$$COLL" >> $(STAGE1_PRTGET_CONFIG_FILE); \
	done
	@echo "writelog enabled" >> $(STAGE1_PRTGET_CONFIG_FILE)
	@echo "logmode overwrite" >> $(STAGE1_PRTGET_CONFIG_FILE)
	@echo "rmlog_on_success no" >> $(STAGE1_PRTGET_CONFIG_FILE)
	@echo "logfile %n-%v-%r.prt-get.log" >> $(STAGE1_PRTGET_CONFIG_FILE)
	@echo "runscripts yes" >> $(STAGE1_PRTGET_CONFIG_FILE)

.PHONY: clean-stage1-prtgetconf
clean-stage1-prtgetconf:
	@rm -f $(STAGE1_PRTGET_CONFIG_FILE)

# Generates a list of ports required to create the stage1
.PHONY: prepare-stage1-ports-file
prepare-stage1-ports-file: $(STAGE1_PORTS_FILE)
$(STAGE1_PORTS_FILE): $(PORTS_DIR)/core $(PORTS_DIR)/core-$(CRUX_ARM_ARCH) $(STAGE1_PRTGET_CONFIG_FILE)
	$(call DEBUG, Preparing $(STAGE1_PORTS_FILE))
	@$(PRTGET_CMD) --config=$(STAGE1_PRTGET_CONFIG_FILE) list > $(STAGE1_PORTS_FILE).tmp-multi-line 2>/dev/null
	@for bl in $(PORTS_BLACKLIST); do \
		sed "/^$$bl/d" -i $(STAGE1_PORTS_FILE).tmp-multi-line; \
	done
	@tr '\n' ' ' < $(STAGE1_PORTS_FILE).tmp-multi-line > $(STAGE1_PORTS_FILE).tmp-one-line
	@$(PRTGET_CMD) --config=$(STAGE1_PRTGET_CONFIG_FILE) quickdep `cat $(STAGE1_PORTS_FILE).tmp-one-line` > $(STAGE1_PORTS_FILE)
	@sed "s|^|$(BUILDTIME_PORTS) |" -i $(STAGE1_PORTS_FILE)
	@rm -f $(STAGE1_PORTS_FILE).tmp*

.PHONY: clean-stage1-ports-file
clean-stage1-ports-file:
	@rm -f $(STAGE1_PORTS_FILE)

$(STAGE1_PACKAGES_DIR):
	@mkdir -vp $(STAGE1_PACKAGES_DIR)

.PHONY: download-stage1-sources
download-stage1-sources: $(STAGE1_PACKAGES_DIR) $(STAGE1_PKGMK_CONFIG_FILE) $(STAGE1_PRTGET_CONFIG_FILE) $(STAGE1_PORTS_FILE)
	$(call DEBUG, Downloading port sources)
	@for PORT in `cat $(STAGE1_PORTS_FILE)`; do \
		portdir=`$(PRTGET_CMD) --config=$(STAGE1_PRTGET_CONFIG_FILE) path "$$PORT"`; \
		( cd $$portdir && $(PKGMK_CMD) -do -cf $(STAGE1_PKGMK_CONFIG_FILE)) || exit 1; \
	done

# Setup a valid rootfs directory to build stage1 packages
.PHONY: prepare-stage1-rootfs-dir
prepare-stage1-rootfs-dir: $(STAGE1_ROOTFS_DIR)
$(STAGE1_ROOTFS_DIR): $(ROOTFS_TAR_FILE) $(STAGE1_PKGMK_CONFIG_FILE) $(STAGE1_PRTGET_CONFIG_FILE)
	$(call DEBUG, Creating $(STAGE1_ROOTFS_DIR))
	@sudo mkdir -vp $(STAGE1_ROOTFS_DIR) || exit 1
	$(call DEBUG, Decompressing $(STAGE0_ROOTFS_TAR_FILE) to $(STAGE1_ROOTFS_DIR))
	@sudo tar -C $(STAGE1_ROOTFS_DIR) -xvf $(STAGE0_ROOTFS_TAR_FILE)
	$(call DEBUG, Installing extras)
	@sudo cp -vL /etc/resolv.conf $(STAGE1_ROOTFS_DIR)/etc/resolv.conf
	@echo "CRUX-ARM $(RELEASE_VERSION)" | sudo tee $(STAGE1_ROOTFS_DIR)/chroot

## 3.8 quirk: rebuild ports that look for libcrypt.so.1
## work around broken packages
## at least perl needs to be uninstalled to be compiled successfully
## it also needs a fix for perls Pkgfile, not sure why yet: sed -i '/perlbug/d' Pkgfile
## https://www.youtube.com/watch?v=zTDeEJyCmNA
.PHONY: fix-problem-packages
fix-problem-packages:
	$(call DEBUG, 3.8 quirk: fixing libcrypt.so.1 and python distutils)
	@for PORT in perl autoconf python3 python3-setuptools ninja meson linux-pam; do \
		needs_rebuild="no"; \
		if [ "$$PORT" = "perl" ]; then \
			portdir=`$(PRTGET_CMD) --config="$(STAGE1_PRTGET_CONFIG_FILE)" path "$$PORT"`; \
			if ldd /usr/lib/perl5/5.*/linux-thread-multi/CORE/libperl.so 2>/dev/null | grep -Eq "libcrypt.so.1|not found"; then \
				needs_rebuild="yes"; \
				$(PRTGET_CMD) --config="$(STAGE1_PRTGET_CONFIG_FILE)" remove "$$PORT"; \
			fi; \
		elif [ "$$PORT" = "linux-pam" ]; then \
			portdir=`$(PRTGET_CMD) --config="$(STAGE1_PRTGET_CONFIG_FILE)" path "$$PORT"`; \
			if ldd /lib/security/pam_unix.so 2>/dev/null | grep -Eq "libcrypt.so.1|not found"; then \
				needs_rebuild="yes"; \
			fi; \
			elif [ "$$PORT" = "python3" ]; then \
				portdir=`$(PRTGET_CMD) --config="$(STAGE1_PRTGET_CONFIG_FILE)" path "$$PORT"`; \
				if ldd /usr/lib/python3.12/lib-dynload/_crypt.cpython-312-aarch64-linux-gnu.so 2>/dev/null | grep -Eq "libcrypt.so.1|not found"; then \
					needs_rebuild="yes"; \
				fi; \
			elif [ "$$PORT" = "python3-setuptools" ]; then \
				portdir=`$(PRTGET_CMD) -if --config="$(STAGE1_PRTGET_CONFIG_FILE)" path "$$PORT"`; \
				needs_rebuild="yes"; \
			else \
				portdir=`$(PRTGET_CMD) --config="$(STAGE1_PRTGET_CONFIG_FILE)" path "$$PORT"`; \
				needs_rebuild="yes"; \
			fi; \
			\
			if [ "$$needs_rebuild" = "yes" ]; then \
				( cd "$$portdir" && \
					$(PKGMK_CMD) -cf "$(STAGE1_PKGMK_CONFIG_FILE)" $(PKGMK_CMD_OPTS) -if \
				) || exit 1; \
			fi; \
			\
			package_name=`grep '^name=' "$$portdir"/Pkgfile | sed 's/name=//'`; \
			package_version=`grep '^version=' "$$portdir"/Pkgfile | sed 's/version=//'`; \
			package_release=`grep '^release=' "$$portdir"/Pkgfile | sed 's/release=//'`; \
			package="$(STAGE1_PACKAGES_DIR)/$$package_name#$$package_version-$$package_release.pkg.tar.$(PKGMK_COMPRESSION_MODE)"; \
			echo "Installing $$package"; \
			if $(PRTGET_CMD) --config="$(STAGE1_PRTGET_CONFIG_FILE)" isinst "$$PORT"; then \
				pkgadd -u "$$package" -f; \
			else \
				pkgadd "$$package" -f; \
			fi; \
	done

# Build all ports in stage1.
# Since ports are built in dependency order, after each port is built, it is installed.
# CAVEAT: This target must be run within the chroot environment as it installs packages
# and could be a serious problem if run outside of the jail.
# NOTE: We don't need targets for $(STAGE1_PACKAGES_DONE_FILE). Everything is passed
# via environment variables; otherwise, it will redo some objectives we don't want to.

.PHONY: build-stage1-packages
build-stage1-packages: $(STAGE1_PACKAGES_DONE_FILE)
$(STAGE1_PACKAGES_DONE_FILE):
	$(call DEBUG, Checking for a valid chroot environment)
	@if [ ! -f /chroot ]; then \
		echo "$(RED)Error: You are not inside chroot environment$(RESET))"; \
		exit 1; \
	fi
	$(call DEBUG, Building stage1 packages from $(STAGE1_PORTS_FILE))
	@for PORT in `cat $(STAGE1_PORTS_FILE)`; do \
		if [ "$$PORT" = "python3-setuptools" ]; then \
			portdir=`$(PRTGET_CMD) -if --config=$(STAGE1_PRTGET_CONFIG_FILE) path "$$PORT"`; \
		else \
			portdir=`$(PRTGET_CMD) --config=$(STAGE1_PRTGET_CONFIG_FILE) path "$$PORT"`; \
			( cd $$portdir && $(PKGMK_CMD) -cf $(STAGE1_PKGMK_CONFIG_FILE) $(PKGMK_CMD_OPTS) ) || exit 1; \
			package_name=`grep '^name=' $$portdir/Pkgfile | sed 's/name=//'`; \
			package_version=`grep '^version=' $$portdir/Pkgfile | sed 's/version=//'`; \
			package_release=`grep '^release=' $$portdir/Pkgfile | sed 's/release=//'`; \
			package="$(STAGE1_PACKAGES_DIR)/$$package_name#$$package_version-$$package_release.pkg.tar.$(PKGMK_COMPRESSION_MODE)"; \
			echo "Installing $$package"; \
			if $(PRTGET_CMD) --config=$(STAGE1_PRTGET_CONFIG_FILE) isinst $$PORT; then \
				pkgadd -u $$package; \
			else \
				pkgadd $$package; \
			fi \
		fi \
	done
	@touch $(STAGE1_PACKAGES_DONE_FILE)

# Create a rootfs file with stage1 packages
.PHONY: build-stage1-rootfs-file
build-stage1-rootfs-file: $(STAGE1_ROOTFS_TAR_FILE)
$(STAGE1_ROOTFS_TAR_FILE): $(STAGE1_PACKAGES_DONE_FILE) $(STAGE1_PRTGET_CONFIG_FILE) $(STAGE1_PORTS_FILE)
	$(call DEBUG, Creating rootfs from stage1 packages: $(STAGE1_ROOTFS_DIR))
	@sudo mkdir -vp $(STAGE1_ROOTFS_DIR) || exit 1
	@sudo mkdir -vp $(STAGE1_ROOTFS_DIR)/var/lib/pkg
	@sudo touch $(STAGE1_ROOTFS_DIR)/var/lib/pkg/db
	@for PORT in `sed "s|$(BUILDTIME_PORTS)||" $(STAGE1_PORTS_FILE)`; do \
		portdir=`$(PRTGET_CMD) --config=$(STAGE1_PRTGET_CONFIG_FILE) path "$$PORT"`; \
		package_name=`grep '^name=' $$portdir/Pkgfile | sed 's/name=//'`; \
		package_version=`grep '^version=' $$portdir/Pkgfile | sed 's/version=//'`; \
		package_release=`grep '^release=' $$portdir/Pkgfile | sed 's/release=//'`; \
		package="$(STAGE1_PACKAGES_DIR)/$$package_name#$$package_version-$$package_release.pkg.tar.$(PKGMK_COMPRESSION_MODE)"; \
		echo "Installing $$package"; \
		sudo pkgadd -r $(STAGE1_ROOTFS_DIR) $$package || exit 1; \
	done
	$(call DEBUG, Creating $(STAGE1_ROOTFS_TAR_FILE))
	@cd $(STAGE1_ROOTFS_DIR) && sudo tar cavf $(STAGE1_ROOTFS_TAR_FILE) *
	@sudo chown $(CURRENT_UID):$(CURRENT_GID) $(STAGE1_ROOTFS_TAR_FILE)

.PHONY: stage1
stage1:
	$(call DEBUG, Downloading sources required to build stage1 packages)
	$(MAKE) -e download-stage1-sources
	$(call DEBUG, Preparing chroot environment ($(STAGE1_ROOTFS_DIR)))
	$(MAKE) -e prepare-stage1-rootfs-dir
	$(call DEBUG, Mounting /dev on $(STAGE1_ROOTFS_DIR)/dev)
	@mountpoint -q $(STAGE1_ROOTFS_DIR)/dev || \
		sudo mount --bind /dev $(STAGE1_ROOTFS_DIR)/dev
	$(call DEBUG, Mounting /proc on $(STAGE1_ROOTFS_DIR)/proc)
	@mountpoint -q $(STAGE1_ROOTFS_DIR)/proc || \
		sudo mount --bind /proc $(STAGE1_ROOTFS_DIR)/proc
	$(call DEBUG, Mounting $(WORKSPACE_DIR)/ports on $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/ports)
	@mkdir -p $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/ports
	@mountpoint -q $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/ports || \
		sudo mount --bind $(WORKSPACE_DIR)/ports $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/ports
	$(call DEBUG, Mounting $(WORKSPACE_DIR)/sources on $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/sources)
	@mkdir -p $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/sources
	@mountpoint -q $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/sources || \
		sudo mount --bind $(WORKSPACE_DIR)/sources $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/sources
	$(call DEBUG, Mounting $(WORKSPACE_DIR)/stage0 on $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/stage0)
	@mkdir -p $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/stage0
	@mountpoint -q $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/stage0 || \
		sudo mount --bind $(WORKSPACE_DIR)/stage0 $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/stage0
	$(call DEBUG, Mounting $(WORKSPACE_DIR)/stage1 on $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/stage1)
	@mkdir -p $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/stage1
	@mountpoint -q $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/stage1 || \
		sudo mount --bind $(WORKSPACE_DIR)/stage1 $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/stage1
	$(call DEBUG, Copying $(WORKSPACE_DIR)/Makefile on $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/Makefile)
	@cp $(WORKSPACE_DIR)/Makefile $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/Makefile
	$(call DEBUG, Setting up chroot environment $(STAGE1_ROOTFS_DIR))
	@env | grep \
		-e ^CRUX_ARM_ARCH \
		-e ^DEVICE_OPTIMIZATION \
		-e ^RELEASE_VERSION \
		-e ^WORKSPACE_DIR \
		-e ^PKGMK_SOURCE_DIR \
		-e ^PKGMK_WORK_DIR > $(STAGE1_ROOTFS_DIR)/.env
	@mkdir -vp $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/work
	$(call DEBUG, Entering chroot environment $(STAGE1_ROOTFS_DIR), fixing faulty packages)
	@sudo chroot $(STAGE1_ROOTFS_DIR) /bin/bash --login -x -e -c \
		"source /.env; cd $(WORKSPACE_DIR) && \
		make -e fix-problem-packages" || exit 1
	$(call DEBUG, Entering chroot environment $(STAGE1_ROOTFS_DIR))
	@sudo chroot $(STAGE1_ROOTFS_DIR) /bin/bash --login -x -e -c \
		"source /.env; cd $(WORKSPACE_DIR) && \
		make -e build-stage1-packages" || exit 1
	$(call DEBUG, Exiting chroot enrivonment)
	$(call DEBUG, Unmounting $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/stage1)
	@sudo umount -f $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/stage1
	$(call DEBUG, Unmounting $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/sources)
	@sudo umount -f $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/sources
	$(call DEBUG, Unmounting $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/ports)
	@sudo umount -f $(STAGE1_ROOTFS_DIR)/$(WORKSPACE_DIR)/ports
	$(call DEBUG, Unmounting $(STAGE1_ROOTFS_DIR)/proc)
	@sudo umount -f $(STAGE1_ROOTFS_DIR)/proc
	$(call DEBUG, Unmounting $(STAGE1_ROOTFS_DIR)/dev)
	@sudo umount -f $(STAGE1_ROOTFS_DIR)/dev
	$(MAKE) -e build-stage1-rootfs-file

.PHONY: clean-stage1
clean-stage1: clean-stage1-pkgmkconf clean-stage1-prtgetconf clean-stage1-ports-file
	@rm $(STAGE1_ROOTFS_TAR_FILE)

#------------------------------------------------------------------------------
# RELEASE
#

.PHONY: release
release: $(RELEASE_TAR_FILE)
$(RELEASE_TAR_FILE): $(STAGE1_ROOTFS_TAR_FILE)
	$(call DEBUG, Release final name $(RELEASE_TAR_FILE))
	@cd $(WORKSPACE_DIR) && ln -sv $(STAGE1_ROOTFS_TAR_FILE) $(RELEASE_TAR_FILE)
	$(call DEBUG, Release completed)

#------------------------------------------------------------------------------
# BOOSTRAP
#

.PHONY: bootstrap
bootstrap:
	$(call DEBUG, Bootstrap started)
	$(call DEBUG, Running Stage 0)
	$(MAKE) -e stage0 2>&1 | tee $(STAGE0_LOG_FILE)
	$(call DEBUG, Running Stage 1)
	$(MAKE) -e stage1 2>&1 | tee $(STAGE1_LOG_FILE)
	$(call DEBUG, Running Release)
	$(MAKE) -e release
	$(call DEBUG, Bootstrap completed)
