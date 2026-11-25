#!/usr/bin/python3
"""Save a monitor layout to ~/.config/hypr/monitors.lua and reload Hyprland.

Usage: layout.py [--scale OUT S] [--transform OUT T] ITEM...
ITEM is a connector name in left-to-right order; "^NAME" stacks NAME above the
item before it instead of placing it to the right. Positions are recomputed from
scratch so nothing overlaps or gaps. Run with --self-test to check the maths.
"""
import json, os, re, shutil, subprocess, sys, tempfile

NAME = re.compile(r"^[A-Za-z0-9._-]+$")


def rule_re(name):
    # [ \t] not \s, so a match never runs onto the next line.
    q = re.escape(name)
    return re.compile(r'^[ \t]*hl\.monitor\(\{[ \t]*output[ \t]*=[ \t]*(["\'])' + q + r'\1[ \t]*,.*$', re.M)


def set_key(line, key, val):
    if re.search(rf"\b{key}[ \t]*=", line):
        return re.sub(rf"\b{key}[ \t]*=[ \t]*[^,}}\s]+", f"{key} = {val}", line, count=1)
    return re.sub(r"[ \t]*\}\)", f", {key} = {val} }})", line, count=1)


def num(line, key):
    m = re.search(rf"\b{key}[ \t]*=[ \t]*([0-9.]+)", line)
    return float(m.group(1)) if m else None


def plan(items, geom):
    """items: [(name, stacked)], geom: {name: (logical_w, logical_h)} -> {name: (x, y)}"""
    columns = []
    for name, stacked in items:
        if name not in geom:
            continue
        if stacked and columns:
            columns[-1].append(name)
        else:
            columns.append([name])
    pos, x = {}, 0
    for col in columns:
        width = max(geom[n][0] for n in col)
        y = 0
        for i, n in enumerate(col):
            w, h = geom[n]
            if i:
                y -= h  # above the previous one
            pos[n] = (x + (width - w) // 2, y)
        x += width
    top = min((p[1] for p in pos.values()), default=0)
    return {n: (px, py - top) for n, (px, py) in pos.items()}


def self_test():
    g = {"L": (1440, 810), "M": (1600, 1000), "R": (1440, 810)}
    assert plan([("L", 0), ("M", 0), ("R", 0)], g) == {"L": (0, 0), "M": (1440, 0), "R": (3040, 0)}
    # R above M: M's column is 1600 wide, R centred over it, everything shifted down by R's height
    assert plan([("L", 0), ("M", 0), ("R", 1)], g) == {"L": (0, 810), "M": (1440, 810), "R": (1520, 0)}
    assert plan([("^X", 1)], g) == {}
    text = ('hl.monitor({ output = "", scale = omarchy_monitor_scale })\n'
            "  hl.monitor({output='DP-1',mode=\"preferred\"}) -- desk\n"
            '-- hl.monitor({ output = "DP-2", scale = 1 })\n'
            'hl.monitor({ output = "DP-3",\n  scale = 2 })\n')
    assert rule_re("DP-1").search(text) and not rule_re("DP-2").search(text) and not rule_re("DP-").search(text)
    line = rule_re("DP-1").search(text).group(0)
    assert num(line, "scale") is None
    assert set_key(set_key(line, "scale", "1.5"), "scale", "2") == "  hl.monitor({output='DP-1',mode=\"preferred\", scale = 2 }) -- desk"
    assert "})" not in rule_re("DP-3").search(text).group(0)  # multi-line: refused in main
    print("self-test ok")


def main(argv):
    if argv == ["--self-test"]:
        return self_test()
    edits = {}
    while argv and argv[0] in ("--scale", "--transform"):
        flag, out, val = argv[:3]
        argv = argv[3:]
        if not NAME.match(out) or not re.match(r"^[0-9]+(\.[0-9]+)?$", val):
            sys.exit(f"bad {flag} {out} {val}")
        edits.setdefault(out, {})["scale" if flag == "--scale" else "transform"] = val
    items = [(a.lstrip("^"), a.startswith("^")) for a in argv]
    if not items or any(not NAME.match(n) for n, _ in items):
        sys.exit("need valid connector names")

    lua = os.path.realpath(os.path.expanduser("~/.config/hypr/monitors.lua"))
    text = open(lua).read()
    live = {m["name"]: m for m in json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"], timeout=5))}
    # A stock monitors.lua only has the catch-all rule: give each monitor we touch its own line.
    for n in sorted({n for n, _ in items} | set(edits)):
        if rule_re(n).search(text):
            continue
        if n not in live:
            sys.exit(f"{n} has no rule in monitors.lua and is not connected")
        text = text.rstrip("\n") + f'\nhl.monitor({{ output = "{n}", mode = "preferred", position = "auto", scale = {round(live[n]["scale"], 6)} }})\n'

    for n in {n for n, _ in items} | set(edits):
        m = rule_re(n).search(text)
        if m and "})" not in m.group(0):
            sys.exit(f"{n}'s rule in monitors.lua spans several lines; put it on one line")

    for n, kv in edits.items():
        text = rule_re(n).sub(lambda m: _apply(m.group(0), kv), text, count=1)

    geom = {}
    for n, _ in items:
        if n not in live:
            continue
        line = rule_re(n).search(text).group(0)
        # scale may be a Lua variable or missing: then Hyprland's live value is the one in use.
        scale = num(line, "scale") or live[n]["scale"]
        t = num(line, "transform")
        if t is None:
            t = live[n]["transform"]
        w, h = round(live[n]["width"] / scale), round(live[n]["height"] / scale)
        geom[n] = (h, w) if int(t) % 2 else (w, h)

    for n, (x, y) in plan(items, geom).items():
        text = rule_re(n).sub(lambda m: set_key(m.group(0), "position", f'"{x}x{y}"'), text, count=1)

    shutil.copy2(lua, lua + ".bak-panel")
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(lua))
    with os.fdopen(fd, "w") as f:
        f.write(text)
    shutil.copymode(lua, tmp)
    os.replace(tmp, lua)
    subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, timeout=5)


def _apply(line, kv):
    for k, v in kv.items():
        line = set_key(line, k, v)
    return line


def notify(msg):
    # The panel ignores our exit code, so a failure would otherwise be a click that does nothing.
    try:
        subprocess.run(["notify-send", "-a", "Displays", "Displays: layout not saved", msg], timeout=5)
    except Exception:
        pass


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except SystemExit as e:
        if e.code not in (None, 0):
            notify(str(e.code))
        raise
    except Exception as e:
        notify(f"{type(e).__name__}: {e}")
        raise
