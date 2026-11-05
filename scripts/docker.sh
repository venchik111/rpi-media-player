#!/bin/bash
# Run any command in the builder container (works from Linux and Git Bash on Windows).
#   scripts/docker.sh scripts/build.sh rpi4
#   scripts/docker.sh scripts/run-qemu-virt.sh
#   scripts/docker.sh bash
set -euo pipefail
cd "$(dirname "$0")/.."
IMAGE=rpi-player-builder
export MSYS_NO_PATHCONV=1
docker build -q -t "$IMAGE" docker/ >/dev/null
SRC_PATH="$(pwd -W 2>/dev/null || pwd)"
TTY=(); [ -t 0 ] && TTY=(-it)
exec docker run --rm "${TTY[@]}" \
	-v "$SRC_PATH":/src -v rpi-player-work:/work -w /src \
	${DOCKER_ARGS:-} "$IMAGE" "$@"
