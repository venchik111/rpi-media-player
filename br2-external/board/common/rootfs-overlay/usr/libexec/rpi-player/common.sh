# Shared helpers for rpi-media-player init scripts (sourced).
ENV_FILE=/run/rpi-player.env
log() { echo "rpi-player: $*"; logger -t rpi-player "$*" 2>/dev/null || true; }
load_env() { [ -f "$ENV_FILE" ] && . "$ENV_FILE"; }
