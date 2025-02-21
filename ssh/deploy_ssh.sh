#!/usr/bin/bash

# run as sudo
cp /etc/ssh/sshd_config /etc/ssh/ssh_config.old
cp ssh/sshd_config.wsl /etc/ssh/sshd_config

# cp /mnt/c/Users/gxbro/OneDrive/Documents/Scratchpad/ssh/authorized_keys /home/gxbrooks/.ssh/authorized_keys
chown gxbrooks:gxbrooks /home/gxbrooks/.ssh/authorized_keys
chmod 600 /home/gxbrooks/.ssh/authorized_keys
