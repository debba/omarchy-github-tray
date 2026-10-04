#!/usr/bin/env bash
set -euo pipefail

REPLACE=0
for argument in "$@"; do
  case "$argument" in
    --replace) REPLACE=1 ;;
    -h|--help)
      echo "Usage: ./install.sh [--replace]"
      echo "--replace explicitly allows backing up and replacing an existing plugin."
      exit 0
      ;;
    *) echo "install.sh: unknown option: $argument" >&2; exit 1 ;;
  esac
done

PLUGIN_ID="community.github-tray"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"

omarchy plugin validate "$SOURCE_DIR"
mkdir -p -- "$(dirname -- "$DEST")"
if [[ "$SOURCE_DIR" != "$(readlink -f -- "$DEST")" ]]; then
  if [[ -e "$DEST" || -L "$DEST" ]]; then
    if (( ! REPLACE )); then
      echo "install.sh: $DEST already exists; leave it untouched or rerun with --replace to back it up first" >&2
      exit 1
    fi
    backup=$(mktemp -d "$(dirname -- "$DEST")/.${PLUGIN_ID}.backup.XXXXXX")
    mv -- "$DEST" "$backup/plugin"
    echo "Existing plugin backed up to $backup/plugin"
  fi
  ln -s -- "$SOURCE_DIR" "$DEST"
fi

chmod +x "$SOURCE_DIR/scripts/github-tray"
omarchy-shell shell rescanPlugins
omarchy plugin enable "$PLUGIN_ID" --section right
echo "GitHub Tray enabled. Configure username and token from its popup or Omarchy bar settings."
