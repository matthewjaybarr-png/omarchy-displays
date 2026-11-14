# Displays

An Omarchy bar widget forked from the stock **Display** panel (`omarchy.monitor`).

The stock panel only scales the monitor under the mouse. This one scales any of them:

- Click the monitor name next to **SCALE** (⇄) to pick which monitor the buttons act on.
- Picking a scale writes it into `~/.config/hypr/monitors.lua` and re-lines the monitors up
  left-to-right, so nothing overlaps (`set-scale.sh`). The previous file is kept as
  `monitors.lua.bak-panel`.
- Includes a 1.33× preset for 1080p screens.

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
