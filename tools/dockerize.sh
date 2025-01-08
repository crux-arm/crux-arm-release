#!/usr/bin/env bash
#
# Run make commands inside a container
# E.g. tools/dockerize.sh stage0 DEVICE_OPTIMIZATION=arm64
#


# Get make command and params
MAKE_PARAMS="help"
[ $# -ge 1 ] && MAKE_PARAMS="$*"

# Device optimizations (see: README.md)
DEVICE_OPTIMIZATION=${DEVICE_OPTIMIZATION:-arm64}

# Get directory tree and setup paths
TOOLS_DIR=$(cd "$(dirname "$0")" && pwd)
BASE_DIR=$(cd "${TOOLS_DIR}"/../ && pwd)

# Detect the host system and fix the necessary requirements if needed
HOST_OS=$(uname -s)
case "${HOST_OS}" in
  "Darwin")
    # Problem:
    #   macOS uses a case-insensitive filesystem (APFS or HFS+), which can cause
    #   issues when bind mounting directories into Docker containers.
    # Fix:
    # - Create a Case-Sensitive APFS Disk Container:
    #   hdiutil create -type SPARSE -fs "Case-sensitive APFS" -size 10g -volname MyDisk mydisk.dmg
    # - Mount the Disk Container:
    #   hdiutil attach mydisk.dmg -mountpoint work/
    # Important Note:
    #  Docker-Desktop v4.37.1 (178610) didn't work and reported a 'mount read-only' issue
    #  Docker-Desktop v4.34.3 (170107) has been tested and worked without problems
    echo "Darwin macOS detected. Checking for mounting volume in ${BASE_DIR}/work"
    echo "Mounting a case-sensitive volume to ${BASE_DIR}/work"
    mkdir -p "${BASE_DIR}/work"
    if [ ! -f "${BASE_DIR}/work.dmg.sparseimage" ]; then
      hdiutil create -type SPARSE -fs "Case-sensitive APFS" -size 10g -volname "crux-arm-release-work" "${BASE_DIR}/work.dmg"
    fi
    hdiutil attach "${BASE_DIR}/work.dmg.sparseimage" -mountpoint "${BASE_DIR}/work" || exit 1
    ;;
esac

# Set workspace dir inside the container
WORKSPACE_DIR="/crux-arm-release"

# Docker builder image and platform
DOCKER_IMAGE=${DOCKER_IMAGE:-sepen/crux:3.7-arm64-builder}
DOCKER_PLATFORM=${DOCKER_PLATFORM:-linux/arm64}

# Run the docker command and bind some directories
# Avoid the whole directory tree of this project to ${WORKSPACE_DIR} since
# this will end up with "too many open files" when managing large docker volumes
docker run --init --rm \
    --platform "${DOCKER_PLATFORM}" \
    -v "${BASE_DIR}/Makefile":${WORKSPACE_DIR}/Makefile \
    -v "${BASE_DIR}/ports":${WORKSPACE_DIR}/ports \
    -v "${BASE_DIR}/devices":${WORKSPACE_DIR}/devices \
    -v "${BASE_DIR}/sources":${WORKSPACE_DIR}/sources \
    -v "${BASE_DIR}/packages":${WORKSPACE_DIR}/packages \
    -v "${BASE_DIR}/work":${WORKSPACE_DIR}/work \
    "${DOCKER_IMAGE}" bash -x -c "
cd ${WORKSPACE_DIR}
make V=1 ${MAKE_PARAMS} DEVICE_OPTIMIZATION=${DEVICE_OPTIMIZATION}
"
