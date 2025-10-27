#!/bin/bash
#
# Assert Spark Events NFS Mount
#
# Ensures /mnt/spark/events is mounted from NFS server for Spark event logging.
# This mount is required for:
#   - Spark drivers to write event logs
#   - Spark History Server to read event logs
#   - Elastic Agent to collect event logs
#
# The NFS share is hosted on Lab2 at /srv/nfs/spark/events
# This script is idempotent and can be run multiple times safely.

# Parse flags
CHECK=false
DEBUG=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --Check|-c) 
          CHECK=true 
          ;;
        --Debug|-d) 
          DEBUG=true 
          ;;
        *) echo "Unknown parameter passed: $1" >&2
          echo "Usage: $0 [--Check|-c] [--Debug|-d]" >&2
          exit 1
          ;;
    esac
    shift
done

# Set the 'dir' variable to the directory of this script
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$dir/.." && pwd)"

# Load NFS server information from environment
if [[ -f "$root_dir/linux/devops_env.sh" ]]; then
  source "$root_dir/linux/devops_env.sh"
  $DEBUG && echo "Debug   : Loaded devops environment"
fi

# Default NFS server (Lab2) - override from environment if available
NFS_SERVER="${NFS_SERVER:-Lab2.lan}"
NFS_EXPORT_EVENTS="/srv/nfs/spark/events"
MOUNT_POINT="/mnt/spark/events"

if $DEBUG; then
  echo "Debug   : NFS_SERVER = $NFS_SERVER"
  echo "Debug   : NFS_EXPORT_EVENTS = $NFS_EXPORT_EVENTS"
  echo "Debug   : MOUNT_POINT = $MOUNT_POINT"
  echo "Debug   : CHECK = $CHECK"
fi

# Check if we're running on the NFS server itself
HOSTNAME=$(hostname)
if [[ "$HOSTNAME" == "Lab2" ]] || [[ "$HOSTNAME" == "lab2" ]]; then
  if $DEBUG; then
    echo "Debug   : Running on NFS server (Lab2), creating symlink and fixing permissions"
  fi
  
  # On Lab2 (NFS server), create symlink from /mnt/spark/events to /srv/nfs/spark/events
  if ! $CHECK; then
    # Ensure NFS export directory exists with correct permissions
    if [[ ! -d "$NFS_EXPORT_EVENTS" ]]; then
      echo "Error   : NFS export directory does not exist: $NFS_EXPORT_EVENTS" >&2
      exit 1
    fi
    
    # Fix permissions on NFS export directory (idempotent)
    CURRENT_PERMS=$(stat -c "%a" "$NFS_EXPORT_EVENTS")
    CURRENT_GROUP=$(stat -c "%G" "$NFS_EXPORT_EVENTS")
    
    if [[ "$CURRENT_GROUP" != "spark" ]] || [[ ! "$CURRENT_PERMS" =~ ^[0-9]7[0-9]$ ]]; then
      echo "Info    : Fixing permissions on $NFS_EXPORT_EVENTS"
      echo "Info    : Current: $CURRENT_GROUP:$CURRENT_PERMS, Target: spark:g+w,g+s"
      
      # Change group to spark
      sudo chgrp spark "$NFS_EXPORT_EVENTS" 2>/dev/null || {
        echo "Error   : Failed to change group to 'spark'. Is the spark group created?" >&2
        exit 1
      }
      
      # Add group write permission and setgid bit
      sudo chmod g+w "$NFS_EXPORT_EVENTS"
      sudo chmod g+s "$NFS_EXPORT_EVENTS"
      
      echo "Info    : Permissions updated: $(stat -c "%A %U:%G" "$NFS_EXPORT_EVENTS")"
    else
      $DEBUG && echo "Debug   : Permissions already correct on $NFS_EXPORT_EVENTS"
    fi
    
    # Create symlink
    if [[ ! -e "$MOUNT_POINT" ]]; then
      echo "Info    : Creating directory structure for symlink..."
      sudo mkdir -p /mnt/spark
      echo "Info    : Creating symlink $MOUNT_POINT -> $NFS_EXPORT_EVENTS"
      sudo ln -s "$NFS_EXPORT_EVENTS" "$MOUNT_POINT"
    elif [[ -L "$MOUNT_POINT" ]]; then
      TARGET=$(readlink "$MOUNT_POINT")
      if [[ "$TARGET" == "$NFS_EXPORT_EVENTS" ]]; then
        $DEBUG && echo "Debug   : Symlink already exists and points to correct location"
      else
        echo "Warning : Symlink exists but points to wrong location ($TARGET)"
        echo "Info    : Recreating symlink..."
        sudo rm "$MOUNT_POINT"
        sudo ln -s "$NFS_EXPORT_EVENTS" "$MOUNT_POINT"
      fi
    elif [[ -d "$MOUNT_POINT" ]] && ! mountpoint -q "$MOUNT_POINT"; then
      echo "Error   : $MOUNT_POINT exists as directory but is not a mount or symlink" >&2
      exit 1
    fi
  else
    echo "Info    : Check mode - would verify symlink and permissions on NFS server"
  fi
  
  exit 0
fi

# For non-NFS-server machines, set up NFS mount
if ! $CHECK; then
  # Install NFS client if not already installed
  if ! dpkg-query -W -f='${Status}' nfs-common 2>/dev/null | grep -q "install ok installed"; then
    echo "Info    : Installing nfs-common package..."
    sudo apt update -qq
    sudo apt install -y nfs-common
  else
    $DEBUG && echo "Debug   : nfs-common already installed"
  fi
  
  # Create mount point directory if it doesn't exist
  if [[ ! -d "$MOUNT_POINT" ]]; then
    echo "Info    : Creating mount point directory: $MOUNT_POINT"
    sudo mkdir -p "$MOUNT_POINT"
  fi
  
  # Check if already mounted
  if mountpoint -q "$MOUNT_POINT"; then
    # Verify it's the correct NFS mount
    current_mount=$(mount | grep "$MOUNT_POINT" | awk '{print $1}')
    expected_mount="${NFS_SERVER}:${NFS_EXPORT_EVENTS}"
    
    if [[ "$current_mount" == "$expected_mount" ]]; then
      echo "Info    : $MOUNT_POINT already mounted from $expected_mount"
    else
      echo "Warning : $MOUNT_POINT mounted from wrong source ($current_mount)"
      echo "Info    : Remounting from correct source..."
      sudo umount "$MOUNT_POINT"
      sudo mount -t nfs "${NFS_SERVER}:${NFS_EXPORT_EVENTS}" "$MOUNT_POINT"
    fi
  else
    # Not mounted, mount it now
    echo "Info    : Mounting ${NFS_SERVER}:${NFS_EXPORT_EVENTS} at $MOUNT_POINT"
    sudo mount -t nfs "${NFS_SERVER}:${NFS_EXPORT_EVENTS}" "$MOUNT_POINT"
    
    if [[ $? -eq 0 ]]; then
      echo "Info    : Successfully mounted NFS share"
    else
      echo "Error   : Failed to mount NFS share" >&2
      exit 1
    fi
  fi
  
  # Add to /etc/fstab if not already present
  FSTAB_ENTRY="${NFS_SERVER}:${NFS_EXPORT_EVENTS} ${MOUNT_POINT} nfs defaults,_netdev 0 0"
  
  if ! grep -q "$MOUNT_POINT" /etc/fstab; then
    echo "Info    : Adding mount to /etc/fstab for persistence..."
    echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab > /dev/null
    echo "Info    : Mount added to /etc/fstab"
  else
    # Check if existing entry is correct
    if ! grep -q "$FSTAB_ENTRY" /etc/fstab; then
      echo "Warning : /etc/fstab has entry for $MOUNT_POINT but with different options"
      echo "Info    : Please manually verify /etc/fstab entry"
    else
      $DEBUG && echo "Debug   : Correct entry already in /etc/fstab"
    fi
  fi
  
  # Verify mount is accessible
  if [[ -d "$MOUNT_POINT" ]] && [[ -r "$MOUNT_POINT" ]]; then
    echo "Info    : Mount verified - $MOUNT_POINT is accessible"
  else
    echo "Error   : Mount exists but is not accessible" >&2
    exit 1
  fi
  
else
  # Check mode
  if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "Info    : Check mode - $MOUNT_POINT is currently mounted"
  elif [[ -L "$MOUNT_POINT" ]]; then
    echo "Info    : Check mode - $MOUNT_POINT is a symlink (running on NFS server)"
  else
    echo "Info    : Check mode - $MOUNT_POINT is NOT mounted (would mount it)"
  fi
fi

echo "Info    : Spark events mount verified"

