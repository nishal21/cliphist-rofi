#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cliphist"
AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/cliphist"

rm -f \
    "$CONFIG_DIR/rofi-clipboard.sh" \
    "$CONFIG_DIR/clipboard.rasi" \
    "$CONFIG_DIR/config" \
    "$AUTOSTART_DIR/cliphist-text.desktop" \
    "$AUTOSTART_DIR/cliphist-images.desktop" \
    "$RUNTIME_DIR/rofi.pid"

echo "Removed cliphist-rofi files."
echo "Pinned snippets kept at: $CONFIG_DIR/pinned.txt"
echo "History cache kept at: $CACHE_DIR (delete manually if you want)"
