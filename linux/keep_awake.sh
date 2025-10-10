#!/bin/bash

# Check if systemd-inhibit is already running
# "inhibiting auto-sleep with systemd-inhibit for native Linux systems."
echo "This is now obsolete. See wake_on_kvm.sh"
exit 1
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

