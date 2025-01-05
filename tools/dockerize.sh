#!/usr/bin/env bash
#
# Run make targets inside docker containers
# E.g. tools/dockerize.sh stage0


TOOLS_DIR=$(cd "$(dirname "$0")" && pwd)
BASE_DIR=$(cd "${TOOLS_DIR}"/../ && pwd)

DEVICE_OPTIMIZATION=${DEVICE_OPTIMIZATION:-arm64}
DOCKER_IMAGE=${DOCKER_IMAGE:-sepen/crux:3.7-arm64-builder}

ULIMIT_VALUE=${ULIMIT_VALUE:-65536}
# ulimit recommendations for Docker and Development
# - Docker Desktop or intensive workloads:
#   65536 to 200000 is common.
# - Heavy builds or high I/O workloads:
#   200000 to 400000 is reasonable.
# - Very high file descriptor usage (databases, large-scale apps):
#   Values up to 524288 can be necessary.
ulimit -n ${ULIMIT_VALUE}

MAKE_PARAMS="bootstrap"
[ $# -ge 1 ] && MAKE_PARAMS="$*"

docker run -it -v "${BASE_DIR}":/crux-arm-release "${DOCKER_IMAGE}" bash -x -c "
export DEVICE_OPTIMIZATION=${DEVICE_OPTIMIZATION}
cd /crux-arm-release
make ${MAKE_PARAMS}
"