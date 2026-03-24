#!/usr/bin/env bash
#
# Custom mouse warping for i3.
# Requires: mouse_warping none in i3 config.
#
# Warps the mouse to the center of the focused window on cross-output
# focus changes, except when the target window is ghostty.
# Requires xdotool.

if ! command -v xdotool &>/dev/null; then
    echo "i3-listener: xdotool is required but not installed" >&2
    exit 1
fi

prev_output=""

i3-msg -t subscribe -m '[ "window" ]' | while read -r line; do
    read -r change class output rect_x rect_y rect_w rect_h < <(echo "$line" | python3 -c "
import sys, json
d = json.load(sys.stdin)
change = d.get('change', '')
c = d.get('container', {})
cls = c.get('window_properties', {}).get('class', '').lower()
output = c.get('output', '')
r = c.get('rect', {})
print(change, cls, output, r.get('x',0), r.get('y',0), r.get('width',0), r.get('height',0))
" 2>/dev/null)

    if [ "$change" != "focus" ]; then
        continue
    fi

    # Cross-output switch: warp mouse unless target is ghostty
    if [ -n "$prev_output" ] && [ "$output" != "$prev_output" ]; then
        if [[ "$class" != *ghostty* ]]; then
            cx=$(( rect_x + rect_w / 2 ))
            cy=$(( rect_y + rect_h / 2 ))
            xdotool mousemove "$cx" "$cy"
        fi
    fi

    prev_output="$output"
done
