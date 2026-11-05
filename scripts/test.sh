#!/bin/bash
# Run the QEMU end-to-end tests (inside the builder container).
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 -m pytest -v tests/ "$@"
