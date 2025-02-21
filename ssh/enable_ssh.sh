#!/usr/bin/bash

# This script must run as root. 

apt update  # Update the package list (important!)
apt install -y openssh-server openssh-client

# use service ssh over systemctgl

systemctl status ssh  # Check status
systemctl enable ssh  # Enable at boot

if [ -n "$WSL_DISTRO_NAME" ]; then
  echo "Running on WSL: Use Windows Defender"
else
  # ufw is installed OOTB on Ubuntu. We check for other varients
  echo "Not running on WSL: Ensure ufw is running"
  command -v ufw >/dev/null 2>&1 \
    || apt install -y ufw && ufw enable && ufw allow ssh
  ufw allow ssh  # If you're using ufw
  ufw enable
  # Code to execute if not on WSL
fi
