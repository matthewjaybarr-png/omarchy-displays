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
    return re.compile(r'^hl\.monitor\(\{ output = "' + re.escape(name) + r'",.*$', re.M)


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
    for n in {n for n, _ in items} | set(edits):
        if not rule_re(n).search(text):
            sys.exit(f"no one-line rule for {n} in monitors.lua")

    def set_key(line, key, val):
        if re.search(rf"\b{key} = ", line):
            return re.sub(rf"\b{key} = [^,}}\s]+", f"{key} = {val}", line)
        return re.sub(r" \}\)", f", {key} = {val} }})", line, count=1)

    for n, kv in edits.items():
        text = rule_re(n).sub(lambda m: _apply(m.group(0), kv, set_key), text, count=1)

    live = {m["name"]: m for m in json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"]))}
    geom = {}
    for n, _ in items:
        if n not in live:
            continue
        line = rule_re(n).search(text).group(0)
        scale = float(re.search(r"\bscale = ([0-9.]+)", line).group(1))
        t = re.search(r"\btransform = ([0-9]+)", line)
        w, h = round(live[n]["width"] / scale), round(live[n]["height"] / scale)
        geom[n] = (h, w) if t and int(t.group(1)) % 2 else (w, h)

    for n, (x, y) in plan(items, geom).items():
        text = rule_re(n).sub(lambda m: set_key(m.group(0), "position", f'"{x}x{y}"'), text, count=1)

    shutil.copy2(lua, lua + ".bak-panel")
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(lua))
    with os.fdopen(fd, "w") as f:
        f.write(text)
    shutil.copymode(lua, tmp)
    os.replace(tmp, lua)
    subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL)


def _apply(line, kv, set_key):
    for k, v in kv.items():
        line = set_key(line, k, v)
    return line


if __name__ == "__main__":
    main(sys.argv[1:])
