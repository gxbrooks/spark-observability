#!/bin/bash

# Check if systemd-inhibit is already running
echo "inhibiting auto-sleep with systemd-inhibit for native Linux systems."
if pgrep -x "systemd-inhibit" > /dev/null; then
    echo "Warning: systemd-inhibit is already running."
else
    # Start systemd-inhibit in the background
    sudo systemd-inhibit \
        --what="sleep:idle" \
        --why="Prevent auto-sleep but allow manual suspend" \
        --mode="block" \
        sleep infinity &
    echo "systemd-inhibit started in the background."
fi

