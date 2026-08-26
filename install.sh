#!/usr/bin/env bash
set -euo pipefail
PLUGIN_ID="community.github-tray"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
mkdir -p "$(dirname "$DEST")"
if [[ -e "$DEST" || -L "$DEST" ]]; then mv "$DEST" "$DEST.backup.$(date +%s)"; fi
ln -s "$SOURCE_DIR" "$DEST"
chmod +x "$SOURCE_DIR/scripts/github-tray"
omarchy plugin validate "$SOURCE_DIR"
omarchy plugin enable "$PLUGIN_ID" --section right
echo "GitHub Tray enabled. Configure username and token from its popup or Omarchy bar settings."
