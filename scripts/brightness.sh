#!/bin/bash
action="$1"

if [ "$action" = "up" ]; then
    brightnessctl s 5%+
elif [ "$action" = "down" ]; then
    brightnessctl s 5%-
fi

pct=$(brightnessctl -m | cut -d, -f4 | tr -d %)

if [ "$pct" -lt 50 ]; then
    icon="brightness-low"
else
    icon="brightness-high"
fi

qs -p /home/merlin/.config/quickshell/waybar-replica ipc call waybarOsd show "$icon,$pct"
