#!/bin/bash

echo "🔍 Enabling USB wakeup support for all capable devices..."

# Step 1: Enable wakeup on all USB devices with power/wakeup
for f in /sys/bus/usb/devices/*/power/wakeup; do
  if [ -f "$f" ]; then
    echo "Enabling wake on: $f"
    echo enabled | sudo tee "$f" > /dev/null
  fi
done

echo "✅ Wake enabled on all applicable USB devices."

# Step 2: Create a persistent udev rule
UDEV_RULE='/etc/udev/rules.d/90-usb-wakeup.rules'
if [ ! -f "$UDEV_RULE" ]; then
  echo "Creating persistent udev rule at $UDEV_RULE"
  sudo bash -c "cat > $UDEV_RULE" <<EOF
# Enable USB device wake support
ACTION=="add", SUBSYSTEM=="usb", TEST=="power/wakeup", ATTR{power/wakeup}="enabled"
EOF
  sudo udevadm control --reload
  echo "✅ Udev rule installed and udev reloaded."
else
  echo "ℹ️ Udev rule already exists at $UDEV_RULE. Skipping."
fi

echo "🎉 USB wakeup configuration complete. You can now test with: systemctl suspend"
