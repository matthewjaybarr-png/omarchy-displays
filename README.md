# Displays

An Omarchy bar widget forked from the stock **Display** panel (`omarchy.monitor`).

The stock panel only scales the monitor under the mouse. This one scales, arranges, stacks and rotates any of them, keeping the stock look:

- Click the monitor name next to **SCALE** (⇄) to pick which monitor the buttons act on.
- Picking a scale writes it into `~/.config/hypr/monitors.lua` and re-lines the monitors up
  left-to-right, so nothing overlaps (`layout.py`). The previous file is kept as
  `monitors.lua.bak-panel`.
- Includes a 1.33× preset for 1080p screens.
- The **Displays** list is in screen order: top = leftmost. Each row has:
  - ↑ / ↓ move that monitor left / right
  - ⤒ stack it above the monitor listed before it (click again to put it back beside it)
  - ▭ / ▯ landscape / portrait
  Every change is saved to `monitors.lua` the same way.

Brightness still follows the focused monitor, same as stock.

## Needs

`monitors.lua` must have a one-line rule per monitor, e.g.

```lua
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "3040x0", scale = 1.333333 })
```

## Install

```sh
ln -s ~/Projects/omarchy-displays ~/.config/omarchy/plugins/matthewjaybarr.displays
```

then add `matthewjaybarr.displays` to the bar in place of `omarchy.monitor`.
