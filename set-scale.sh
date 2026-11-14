#!/bin/bash
# Usage: set-scale.sh <output> <scale>        set one monitor's scale
#        set-scale.sh --order <output>...     set the left-to-right order
# Edits ~/.config/hypr/monitors.lua, then re-packs the active monitors left-to-right
# (current order unless --order is given) so nothing overlaps or gaps.
set -euo pipefail
lua="$(readlink -f "$HOME/.config/hypr/monitors.lua")"
name_ok() { [[ $1 =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad output name: $1" >&2; exit 1; }; }
has_rule() { grep -q "^hl.monitor({ output = \"$1\"," "$lua" || { echo "no rule for $1 in monitors.lua" >&2; exit 1; }; }

monitors="$(hyprctl monitors -j)"
output="" scale=""
if [[ ${1:-} == --order ]]; then
  shift
  (( $# )) || { echo "--order needs outputs" >&2; exit 1; }
  for o in "$@"; do name_ok "$o"; has_rule "$o"; done
  order=("$@")
else
  output="${1:?output}" scale="${2:?scale}"
  name_ok "$output"; has_rule "$output"
  [[ $scale =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "bad scale" >&2; exit 1; }
  mapfile -t order < <(jq -r 'sort_by(.x) | .[].name' <<<"$monitors")
fi

cp "$lua" "$lua.bak-panel"
tmp="$(mktemp "$lua.XXXXXX")"
cp "$lua" "$tmp"
[[ -n $output ]] && sed -i -E "/^hl.monitor\(\{ output = \"$output\",/ s/scale = [0-9.]+/scale = $scale/" "$tmp"

# Logical width = pixel width / scale (rounded, as Hyprland does).
x=0
for name in "${order[@]}"; do
  width=$(jq -r --arg n "$name" '.[] | select(.name == $n) | .width' <<<"$monitors")
  s=$(grep -oP "^hl.monitor\(\{ output = \"$name\",.*scale = \K[0-9.]+" "$tmp" || true)
  [[ -n $width && -n $s ]] || continue
  sed -i -E "/^hl.monitor\(\{ output = \"$name\",/ s/position = \"[^\"]*\"/position = \"${x}x0\"/" "$tmp"
  x=$(( x + $(awk -v w="$width" -v s="$s" 'BEGIN { printf "%d", w / s + 0.5 }') ))
done

chmod --reference="$lua" "$tmp"
mv "$tmp" "$lua"
hyprctl reload >/dev/null
