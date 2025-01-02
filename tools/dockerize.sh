#!/usr/bin/env bash

TOOLS_DIR=$(cd "$(dirname "$0")" && pwd)
BASE_DIR=$(cd "${TOOLS_DIR}"/../ && pwd)

DEVICE_OPTIMIZATION=${DEVICE_OPTIMIZATION:-arm64}
DOCKER_IMAGE="sepen/crux:3.7-${DEVICE_OPTIMIZATION}-builder"

MAKE_PARAMS="bootstrap"
[ $# -ge 1 ] && MAKE_PARAMS="$*"

docker run -it -v "${BASE_DIR}":/crux-arm-release "${DOCKER_IMAGE}" bash -c "
cd /crux-arm-release
make ${MAKE_PARAMS}
"