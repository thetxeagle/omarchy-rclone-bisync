#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SOURCE="$SCRIPT_DIR/quickshell/eagle.rclone-bisync"
PLUGIN_TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/eagle.rclone-bisync"

for required_command in omarchy omarchy-shell python3; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "$required_command is required on an Omarchy desktop." >&2
        exit 1
    fi
done

mkdir -p "$PLUGIN_TARGET"
install -m 644 "$PLUGIN_SOURCE/manifest.json" "$PLUGIN_SOURCE/BarWidget.qml" "$PLUGIN_TARGET/"
install -m 755 "$PLUGIN_SOURCE/status.py" "$PLUGIN_TARGET/"

omarchy-shell shell rescanPlugins
omarchy bar put eagle.rclone-bisync --section right

echo "Installed eagle.rclone-bisync and placed it on the right side of the Omarchy bar."
