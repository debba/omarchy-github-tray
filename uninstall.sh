#!/usr/bin/env bash
set -euo pipefail
PLUGIN_ID="community.github-tray"
omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || true
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
[[ -L "$DEST" ]] && rm "$DEST"
echo "GitHub Tray disabled and development symlink removed."
