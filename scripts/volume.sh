#!/bin/bash
action="$1"

if [ "$action" = "up" ]; then
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5
elif [ "$action" = "down" ]; then
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-
elif [ "$action" = "toggle" ]; then
    wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
fi

status=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
vol_pct=$(echo "$status" | awk '{print int($2 * 100)}')

if echo "$status" | grep -q "\[MUTED\]"; then
    icon="volume-mute"
elif [ "$vol_pct" -eq 0 ]; then
    icon="volume-mute"
elif [ "$vol_pct" -lt 50 ]; then
    icon="volume-low"
else
    icon="volume-high"
fi

qs -p /home/merlin/.config/quickshell/waybar-replica ipc call waybarOsd show "$icon,$vol_pct"
