# COSMIC setup

Extra notes if you run this on System76 COSMIC.

## Shortcut

1. Open **Settings → Keyboard → Shortcuts**
2. Add a custom shortcut
3. Key: **Super+V** (or your choice)
4. Command: `/home/YOUR_USER/.config/cliphist/rofi-clipboard.sh`

Replace `YOUR_USER` with your actual username. Do not copy a path from another machine.

## Clipboard daemons

`install.sh` drops two autostart entries:

- `cliphist-text.desktop` watches text copies
- `cliphist-images.desktop` watches image copies

They should start on login. If history stays empty, check that both are enabled in your autostart settings.

## Paste focus

If rofi closes but nothing pastes into the field you had open:

1. Confirm `wtype` is installed
2. Log out and back in after install (for `COSMIC_DATA_CONTROL_ENABLED`)
3. Try copying manually with Enter in the picker and paste with Ctrl+V to see if the issue is wl-copy or wtype

## Theming

Edit `~/.config/cliphist/clipboard.rasi`. Window width, anchor (`location: east`), and line count live in the `window` and `listview` blocks.
