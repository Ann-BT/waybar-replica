#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: $0 <path_to_wallpaper>"
    exit 1
fi

WALLPAPER="$1"

# Kill video wallpaper if running to prevent it from overlaying the static wallpaper
pkill -f -9 mpvpaper || true

# Start hyprpaper if not running
if ! pgrep -x "hyprpaper" > /dev/null; then
    setsid hyprpaper -c /home/merlin/.config/hypr/hyprpaper.conf > /dev/null 2>&1 &
    sleep 0.5
fi

# Apply wallpaper using hyprctl hyprpaper for each active monitor
for monitor in $(hyprctl monitors -j | jq -r '.[] | .name'); do
    hyprctl hyprpaper wallpaper "$monitor,$WALLPAPER"
done

# Run matugen to generate color schemes
matugen image "$WALLPAPER"

# Apply Material You theme to KDE/Qt applications (like Dolphin)
bash "$HOME/.config/matugen/templates/kde/kde-material-you-colors-wrapper.sh"

# Reload all active Kitty terminal instances to apply the new theme instantly
killall -USR1 kitty || true
