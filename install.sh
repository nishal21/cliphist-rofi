#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cliphist"
AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
ENV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing dependency: $1" >&2
        exit 1
    }
}

for bin in cliphist rofi wl-copy wl-paste wtype; do
    need "$bin"
done

mkdir -p "$CONFIG_DIR" "$AUTOSTART_DIR" "$ENV_DIR"

install -m 755 "$ROOT/bin/rofi-clipboard.sh" "$CONFIG_DIR/rofi-clipboard.sh"
install -m 644 "$ROOT/theme/clipboard.rasi" "$CONFIG_DIR/clipboard.rasi"
install -m 644 "$ROOT/config/config" "$CONFIG_DIR/config"

if [[ ! -f "$CONFIG_DIR/pinned.txt" ]]; then
    install -m 644 "$ROOT/config/pinned.txt.example" "$CONFIG_DIR/pinned.txt"
fi

install -m 644 "$ROOT/autostart/cliphist-text.desktop" "$AUTOSTART_DIR/"
install -m 644 "$ROOT/autostart/cliphist-images.desktop" "$AUTOSTART_DIR/"

if [[ ! -f "$ENV_DIR/90-cosmic-clipboard.conf" ]]; then
    cat >"$ENV_DIR/90-cosmic-clipboard.conf" <<'EOF'
# Helps wl-copy restore focus on COSMIC after the clipboard picker closes.
COSMIC_DATA_CONTROL_ENABLED=1
EOF
fi

echo "Installed to $CONFIG_DIR"
echo ""
echo "Bind a shortcut to:"
echo "  $CONFIG_DIR/rofi-clipboard.sh"
echo ""
echo "Suggested key: Super+V"
echo "Log out and back in if paste focus is wrong on COSMIC."
