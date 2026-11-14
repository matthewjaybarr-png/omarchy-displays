#!/bin/bash
# Usage: set-scale.sh <output> <scale>
# Sets one monitor's scale in ~/.config/hypr/monitors.lua, then re-packs the active
# monitors left-to-right in their current order so nothing overlaps or gaps.
set -euo pipefail
output="$1" scale="$2"
lua="$(readlink -f "$HOME/.config/hypr/monitors.lua")"

[[ $output =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad output name" >&2; exit 1; }
[[ $scale =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "bad scale" >&2; exit 1; }
grep -q "^hl.monitor({ output = \"$output\"," "$lua" || { echo "no rule for $output in monitors.lua" >&2; exit 1; }

cp "$lua" "$lua.bak-panel"
tmp="$(mktemp "$lua.XXXXXX")"
cp "$lua" "$tmp"
sed -i -E "/^hl.monitor\(\{ output = \"$output\",/ s/scale = [0-9.]+/scale = $scale/" "$tmp"

# Logical width = pixel width / scale (rounded, as Hyprland does); walk left to right.
x=0
while read -r name width; do
  s=$([[ $name == "$output" ]] && echo "$scale" || grep -oP "^hl.monitor\(\{ output = \"$name\",.*scale = \K[0-9.]+" "$tmp" || true)
  [[ -n $s ]] || continue
  sed -i -E "/^hl.monitor\(\{ output = \"$name\",/ s/position = \"[^\"]*\"/position = \"${x}x0\"/" "$tmp"
  x=$(( x + $(awk -v w="$width" -v s="$s" 'BEGIN { printf "%d", w / s + 0.5 }') ))
done < <(hyprctl monitors -j | jq -r 'sort_by(.x) | .[] | "\(.name) \(.width)"')

chmod --reference="$lua" "$tmp"
mv "$tmp" "$lua"
hyprctl reload >/dev/null
