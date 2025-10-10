#!/bin/bash
#
# wake_on_kvm.sh — Keep Ubuntu mini-PC displays & USB awake under KVM switches
#
# Features:
#   • Prevents screen blanking & DPMS video shutdown
#   • Keeps HDMI output active even if disconnected by KVM
#   • Enables USB keyboard/mouse wake persistently
#   • Blocks system auto-sleep via systemd-inhibit
#   • Idempotent: safe to run repeatedly
#   • Logs all actions to /var/log/wake_on_kvm.log
#
# Requires: sudo privileges

set -euo pipefail
LOGFILE="/var/log/wake_on_kvm.log"
mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee -a "$LOGFILE") 2>&1
echo "========== $(date): Running wake_on_kvm.sh =========="

#############################################
# 1. Prevent auto-sleep via systemd-inhibit
#############################################
if pgrep -x "systemd-inhibit" > /dev/null; then
    echo "✓ systemd-inhibit already running"
else
    echo "→ Starting systemd-inhibit to block sleep"
    sudo systemd-inhibit --what="sleep:idle" \
        --why="Prevent auto-sleep but allow manual suspend" \
        --mode="block" \
        sleep infinity &
fi


#############################################
# 2. Disable screen blanking & DPMS
#############################################
XPROFILE="$HOME/.xprofile"
XSET_CMD='xset s off -dpms s noblank'

if grep -qF "$XSET_CMD" "$XPROFILE" 2>/dev/null; then
    echo "✓ Screen blanking already disabled in $XPROFILE"
else
    echo "→ Adding screen blanking disable commands to $XPROFILE"
    echo "$XSET_CMD" >> "$XPROFILE"
fi


#############################################
# 3. Force HDMI output to stay active
#############################################
XORG_CONF_DIR="/usr/share/X11/xorg.conf.d"
MONITOR_CONF="$XORG_CONF_DIR/10-monitor.conf"
HDMI_OUT=$(xrandr | awk '/ connected/{print $1; exit}')

if [ -z "$HDMI_OUT" ]; then
    echo "⚠️  No active HDMI output detected via xrandr, skipping HDMI config"
else
    echo "Detected HDMI output: $HDMI_OUT"
    if [ -f "$MONITOR_CONF" ] && grep -q "$HDMI_OUT" "$MONITOR_CONF"; then
        echo "✓ HDMI config already present in $MONITOR_CONF"
    else
        echo "→ Writing persistent HDMI configuration to $MONITOR_CONF"
        sudo mkdir -p "$XORG_CONF_DIR"
        sudo tee "$MONITOR_CONF" > /dev/null <<EOF
Section "Monitor"
    Identifier "$HDMI_OUT"
    Option "DPMS" "false"
EndSection

Section "Device"
    Identifier "Intel Graphics"
    Driver "modesetting"
    Option "HotPlug" "false"
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Option "AutoAddGPU" "false"
EndSection
EOF
    fi
fi


#############################################
# 4. Enable USB wake for all devices
#############################################
echo "🔍 Enabling USB wakeup support for all capable devices..."

for f in /sys/bus/usb/devices/*/power/wakeup; do
  if [ -f "$f" ]; then
    current=$(cat "$f")
    if [ "$current" != "enabled" ] && [ "$current" != "on" ]; then
      echo "→ Enabling wake on: $f"
      echo enabled | sudo tee "$f" > /dev/null
    fi
  fi
done
echo "✓ USB wake enabled for all applicable devices"

# Persistent udev rule
UDEV_RULE='/etc/udev/rules.d/90-usb-wakeup.rules'
UDEV_CONTENT='# Enable USB device wake support
ACTION=="add", SUBSYSTEM=="usb", TEST=="power/wakeup", ATTR{power/wakeup}="enabled"'

if [ -f "$UDEV_RULE" ] && grep -q "power/wakeup" "$UDEV_RULE"; then
    echo "✓ Persistent udev rule already exists at $UDEV_RULE"
else
    echo "→ Creating persistent udev rule at $UDEV_RULE"
    echo "$UDEV_CONTENT" | sudo tee "$UDEV_RULE" > /dev/null
    sudo udevadm control --reload
    echo "✓ Udev rule installed and reloaded"
fi


#############################################
# 5. Disable system sleep targets (persistent)
#############################################
mask_targets=(sleep.target suspend.target hibernate.target hybrid-sleep.target)

for target in "${mask_targets[@]}"; do
    if systemctl is-enabled "$target" 2>/dev/null | grep -q masked; then
        echo "✓ $target already masked"
    else
        echo "→ Masking $target"
        sudo systemctl mask "$target"
    fi
done


#############################################
# 6. Optional: ensure xrandr auto-refresh command exists
#############################################
XRANDR_SCRIPT="/usr/local/bin/refresh_display.sh"
if [ ! -f "$XRANDR_SCRIPT" ]; then
    echo "→ Creating helper to refresh HDMI display: $XRANDR_SCRIPT"
    sudo tee "$XRANDR_SCRIPT" > /dev/null <<EOF
#!/bin/bash
# Reinitialize display after KVM switch
xrandr --auto
EOF
    sudo chmod +x "$XRANDR_SCRIPT"
fi


#############################################
# 7. Completion
#############################################
echo "✅ wake_on_kvm.sh complete. HDMI/USB wake persistence and anti-sleep settings applied."
echo "Log written to: $LOGFILE"
