# Displays

The stock Omarchy **Display** panel, made for multi-monitor setups: it works with every
monitor you have plugged in.

**It stays simple on purpose.** Same look, same place on the bar, same brightness and
text-size controls. No new windows, no settings page, no layout canvas to drag around, no
extra packages: just a few small buttons on the list that's already there. What it adds:

- **Scale any monitor.** The stock panel only scales the monitor under the mouse. Here you
  pick the monitor first.
- **Arrange them.** Change the left-to-right order.
- **Stack them.** Put one monitor above another.
- **Portrait or landscape.** One click per monitor.

Every change is saved to `~/.config/hypr/monitors.lua`, so it survives a reboot, and the
monitors are lined up again each time so they never overlap or leave a gap.

![The Displays panel: brightness, text size, scale with the monitor picker, and the display list with move, stack and rotate buttons](preview.png)

Built against Omarchy 4.5.0 (Hyprland 0.56.2, Quickshell 0.3.2). Forked from the stock
`omarchy.monitor` panel.

## Install

```bash
omarchy plugin add https://github.com/matthewjaybarr-png/omarchy-displays.git
omarchy plugin enable matthewjaybarr.displays
omarchy bar put matthewjaybarr.displays --after omarchy.monitor
omarchy plugin disable omarchy.monitor
```

Plugins land disabled so you can read the code first; `enable` is the second step on
purpose. The last two lines put Displays on the bar where the stock Display icon was and
turn the stock one off. Turning it off also lets Displays answer the brightness keys,
which call the panel by the stock name.

To go back: `omarchy plugin enable omarchy.monitor` and
`omarchy plugin disable matthewjaybarr.displays`.

## Using it

Click the monitor icon on the bar.

**Pick a monitor.** With more than one monitor, a row of buttons at the top picks the
one the panel works on. Below it is everything about that monitor: its make and model,
resolution, refresh rate, scale, the size it looks like, orientation and position, and
whether it's mirroring another or has your mouse focus.

**Name it.** Click the pencil next to the name to give the monitor your own name ("Left
desk"), Enter to save, Esc to cancel, empty to go back to the port name. Names are tied to
the screen itself, not the port, so they follow it if you plug it in elsewhere. They're
kept in `~/.config/omarchy/displays-aliases.json`.

**Scale** and **Refresh rate** change the picked monitor. There's a 1.33× button for
1080p screens. Refresh rate only shows when the monitor offers more than 60 Hz at its
current resolution.

**Displays list.** The list is in screen order: the top row is the leftmost monitor. Each
row has:

| Button | Does |
|---|---|
| ↑ / ↓ | move the monitor one place left / right |
| ⤒ | stack it above the monitor listed before it; bright when on, click again to undo |
| ▭ / ▯ | landscape / portrait; shows which it is now |
| ⧉ | mirror: show the built-in screen's picture (or the first monitor's) on this one; click again to extend |
| click the name | turn the monitor on or off, same as stock |

You can also drag a row up or down to move it.

A stacked monitor sits centred above the one before it in the list. To put a monitor above
your laptop, move it to just after the laptop with ↑ / ↓, then press ⤒.

**Brightness** still follows the monitor your mouse is on, same as stock.

## How it saves

`layout.py` (Python 3, standard library only) does all the writing:

- It changes only the `hl.monitor({ output = "NAME", ... })` line of each monitor, one line
  each. Monitors that don't have a line yet get one added at the end of the file. Your other
  lines are left alone.
- The previous file is kept as `~/.config/hypr/monitors.lua.bak-panel`. Copy it back over
  `monitors.lua` to undo the last change.
- Monitors are told apart by connector name (`HDMI-A-1`, `DP-3`, ...), not by model, so two
  identical monitors work fine. If you swap cables between ports, the two swap places.

Check the maths with `./layout.py --self-test`.

## Releases

Each release is submitted to the
[Omarchy plugin marketplace](https://github.com/omacom/omarchy-plugin-marketplace) for review.

| Version | Commit | Submission | Status |
| --- | --- | --- | --- |
| 0.3.2 | `6f90582` | [#15923](https://github.com/omacom/omarchy-plugin-marketplace/issues/15923) | Under review |
| 0.3.1 | `b2e57be` | [#14994](https://github.com/omacom/omarchy-plugin-marketplace/issues/14994) | Verified |

## License

MIT. Includes code from Omarchy's `omarchy.monitor` panel, also MIT.
