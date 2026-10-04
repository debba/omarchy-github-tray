#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="community.github-tray"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"

if [[ -e "$DEST" || -L "$DEST" ]]; then
  if [[ ! -L "$DEST" || "$(readlink -f -- "$DEST")" != "$SOURCE_DIR" ]]; then
    echo "uninstall.sh: refusing to remove an unrelated installation at $DEST" >&2
    echo "For a plugin-manager installation, use: omarchy plugin remove $PLUGIN_ID" >&2
    exit 1
  fi
  omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || true
  rm -- "$DEST"
  omarchy-shell shell rescanPlugins 2>/dev/null || true
  echo "GitHub Tray disabled and development symlink removed."
else
  echo "GitHub Tray development symlink is not installed."
fi
