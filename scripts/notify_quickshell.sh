#!/bin/bash
echo "Script executed at $(date): app=$SWAYNC_APP_NAME, summary=$SWAYNC_SUMMARY, body=$SWAYNC_BODY" >> /tmp/notify_script.log
/usr/bin/qs -p /home/merlin/.config/quickshell/waybar-replica ipc call notificationService display "$SWAYNC_APP_NAME" "$SWAYNC_SUMMARY" "$SWAYNC_BODY" >> /tmp/notify_script.log 2>&1
