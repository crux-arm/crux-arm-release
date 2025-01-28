#!/usr/bin/env bash
#
# Run make commands inside a container
# E.g. tools/dockerize.sh stage0 DEVICE_OPTIMIZATION=arm64
#

# Get make command
MAKE_PARAMS="help"
if [ $# -ge 1 ]; then
  # all arguments as a single string
  MAKE_PARAMS="$*"
  # all arguments preserving their structure
  INPUT_ARGS="$@"
fi

# Device optimizations (see: README.md)
DEVICE_OPTIMIZATION=${DEVICE_OPTIMIZATION:-arm64}

# Get directory tree and setup paths
TOOLS_DIR=$(cd "$(dirname "$0")" && pwd)
BASE_DIR=$(cd "${TOOLS_DIR}"/../ && pwd)

# Set workspace dir inside the container
WORKSPACE_DIR="/crux-arm-release"

# Docker builder image and platform
DOCKER_IMAGE=${DOCKER_IMAGE:-sepen/crux:3.7-updated-arm64-builder}
DOCKER_PLATFORM=${DOCKER_PLATFORM:-linux/arm64}

# Detect the host system and fix the necessary requirements if needed
HOST_OS=$(uname -s)
case "${HOST_OS}" in
  "Darwin")
    # macOS uses uses a case-insensitive filesystem which can cause issues when bind
    # mounting directories into containers, for example with 'mknod' commands
    # We should use a directory from the container not being mounted
    STAGE0_PKGMK_WORK_DIR="/var/lib/pkg/work"
    STAGE1_PKGMK_WORK_DIR="/var/lib/pkg/work"

    # Run the docker command and bind some directories
    # Avoid the whole directory tree of this project to ${WORKSPACE_DIR} since
    # this will end up with "too many open files" when managing large docker volumes
    case "$1" in
    "debug"|"shell")
      docker run --init --privileged --rm -it \
        --platform "${DOCKER_PLATFORM}" \
        -v "${BASE_DIR}/Makefile":${WORKSPACE_DIR}/Makefile \
        -v "${BASE_DIR}/devices":${WORKSPACE_DIR}/devices \
        -v "${BASE_DIR}/ports":${WORKSPACE_DIR}/ports \
        -v "${BASE_DIR}/sources":${WORKSPACE_DIR}/sources \
        -v "${BASE_DIR}/logs":${WORKSPACE_DIR}/logs \
        -v "${BASE_DIR}/stage0":${WORKSPACE_DIR}/stage0 \
        -v "${BASE_DIR}/stage1":${WORKSPACE_DIR}/stage1 \
        -v "${BASE_DIR}/stagefinal":${WORKSPACE_DIR}/stagefinal \
        -v "${BASE_DIR}/quirks":${WORKSPACE_DIR}/quirks \
        -v "${BASE_DIR}/release":${WORKSPACE_DIR}/release \
        "${DOCKER_IMAGE}" bash
    ;;
    *)
      docker run --init --privileged --rm \
        --platform "${DOCKER_PLATFORM}" \
        -v "${BASE_DIR}/Makefile":${WORKSPACE_DIR}/Makefile \
        -v "${BASE_DIR}/devices":${WORKSPACE_DIR}/devices \
        -v "${BASE_DIR}/ports":${WORKSPACE_DIR}/ports \
        -v "${BASE_DIR}/sources":${WORKSPACE_DIR}/sources \
        -v "${BASE_DIR}/logs":${WORKSPACE_DIR}/logs \
        -v "${BASE_DIR}/stage0":${WORKSPACE_DIR}/stage0 \
        -v "${BASE_DIR}/stage1":${WORKSPACE_DIR}/stage1 \
        -v "${BASE_DIR}/stagefinal":${WORKSPACE_DIR}/stagefinal \
        -v "${BASE_DIR}/quirks":${WORKSPACE_DIR}/quirks \
        -v "${BASE_DIR}/release":${WORKSPACE_DIR}/release \
        "${DOCKER_IMAGE}" bash -x -c "

        # Disable sudo password prompt
        echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel

        cd ${WORKSPACE_DIR} && \
          mkdir -p ${STAGE0_PKGMK_WORK_DIR} \
            ${STAGE1_PKGMK_WORK_DIR}
          make V=1 ${MAKE_PARAMS} \
            STAGE0_PKGMK_WORK_DIR=${STAGE0_PKGMK_WORK_DIR} \
            STAGE1_PKGMK_WORK_DIR=${STAGE1_PKGMK_WORK_DIR}
        "
    ;;
    esac
  ;;
  # Linux hosts only need a volume, our workspace directory
  # We remove the --init option which causes problems starting the container
  *)
    case "$1" in
    "debug"|"shell")
      docker run --privileged --rm -it \
        --platform "${DOCKER_PLATFORM}" \
        -v "${BASE_DIR}":${WORKSPACE_DIR} \
        "${DOCKER_IMAGE}" bash
    ;;
    *)
      docker run --privileged --rm -it \
        --platform "${DOCKER_PLATFORM}" \
        -v "${BASE_DIR}":${WORKSPACE_DIR} \
        "${DOCKER_IMAGE}" bash -x -c "

      # Disable sudo password prompt
      echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel

      cd ${WORKSPACE_DIR} && \
        make V=1 ${MAKE_PARAMS}
      "
    ;;
    esac
esac
