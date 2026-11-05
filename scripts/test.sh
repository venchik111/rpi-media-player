#!/bin/bash
# Full verification without hardware (run inside the builder container):
#   1. static audit of the Pi SD image (firmware, modules, boot files, layout)
#   2. Pi image boots on QEMU raspi4b (Pi kernel + DTB)
#   3. end-to-end tests on the *Pi rootfs* under QEMU virt with simulated Wi-Fi
# Usage: scripts/test.sh [audit|boot|e2e|all] [pytest args...]
set -euo pipefail
cd "$(dirname "$0")/.."
what="${1:-all}"; shift || true
case "$what" in
	audit) exec scripts/audit-image.sh ;;
	boot) exec scripts/test-raspi4b-boot.sh ;;
	e2e) exec python3 -m pytest -v -p no:cacheprovider tests/ "$@" ;;
	all)
		scripts/audit-image.sh
		scripts/test-raspi4b-boot.sh
		python3 -m pytest -v -p no:cacheprovider tests/ "$@"
		;;
	*) echo "usage: $0 [audit|boot|e2e|all]" >&2; exit 1 ;;
esac
