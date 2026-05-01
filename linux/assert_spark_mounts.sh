#!/bin/bash
#
# Assert Spark NFS mounts and ownership contract.
#
# Ensures required /mnt/spark subdirectories are mounted from NFS exports and
# that mounted directories resolve to spark:spark with group-writable setgid perms.
#

set -euo pipefail

CHECK=false
DEBUG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --Check|-c)
      CHECK=true
      ;;
    --Debug|-d)
      DEBUG=true
      ;;
    *)
      echo "Unknown parameter passed: $1" >&2
      echo "Usage: $0 [--Check|-c] [--Debug|-d]" >&2
      exit 1
      ;;
  esac
  shift
done

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$dir/.." && pwd)"

if ! $CHECK; then
  echo "Info    : Regenerating devops context for NFS/server variables..."
  (cd "$root_dir" && bash vars/generate_contexts.sh devops -f) || true
fi

DEVOPS_ENV_FILE="$root_dir/vars/contexts/devops_env.sh"
if [[ -f "$DEVOPS_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$DEVOPS_ENV_FILE"
  $DEBUG && echo "Debug   : Loaded devops environment from $DEVOPS_ENV_FILE"
fi

if [[ -z "${NFS_SERVER:-}" ]]; then
  echo "Error   : NFS_SERVER is not set. Regenerate and source vars/contexts/devops_env.sh" >&2
  exit 1
fi

NFS_MOUNT_OPTS="nfsvers=4,defaults,_netdev"

MOUNT_POINTS=(
  "/mnt/spark/events:/srv/nfs/spark/events"
  "/mnt/spark/data:/srv/nfs/spark/data"
  "/mnt/spark/logs:/srv/nfs/spark/logs"
  "/mnt/spark/checkpoints:/srv/nfs/spark/checkpoints"
  "/mnt/spark/jupyter:/srv/nfs/jupyterhub"
)

EXPECTED_OWNER="spark"
EXPECTED_GROUP="spark"
FAILURES=0

_host_short="$(hostname -s 2>/dev/null || hostname)"
_host_short="${_host_short,,}"
_nfs_short="${NFS_SERVER%%.*}"
_nfs_short="${_nfs_short,,}"
IS_NFS_SERVER=false
if [[ "$_host_short" == "$_nfs_short" ]]; then
  IS_NFS_SERVER=true
fi
unset _host_short _nfs_short

ensure_mode_contract() {
  local target="$1"
  if [[ ! -e "$target" ]]; then
    return 1
  fi

  local owner group perms perms_text
  owner="$(stat -c "%U" "$target")"
  group="$(stat -c "%G" "$target")"
  perms="$(stat -c "%a" "$target")"
  perms_text="$(stat -c "%A" "$target")"

  local group_write='no'
  local setgid='no'
  [[ "${perms_text:5:1}" == "w" || "${perms_text:6:1}" == "s" || "${perms_text:6:1}" == "S" ]] && group_write='yes'
  [[ "${perms_text:6:1}" == "s" || "${perms_text:6:1}" == "S" ]] && setgid='yes'

  if [[ "$owner" == "$EXPECTED_OWNER" && "$group" == "$EXPECTED_GROUP" && "$group_write" == "yes" && "$setgid" == "yes" ]]; then
    $DEBUG && echo "Debug   : Ownership/perms ok on $target ($owner:$group $perms)"
    return 0
  fi

  if $CHECK; then
    echo "Check   : $target ownership/perms mismatch ($owner:$group $perms), expected ${EXPECTED_OWNER}:${EXPECTED_GROUP} with group write + setgid"
    return 1
  fi

  echo "Info    : Fixing ownership/perms on $target (current $owner:$group $perms)"
  sudo chown "$EXPECTED_OWNER:$EXPECTED_GROUP" "$target"
  sudo chmod g+rwxs "$target"
  return 0
}

_nfs_umount() {
  local mp="$1"
  if mountpoint -q "$mp" 2>/dev/null; then
    echo "Info    : Unmounting $mp (lazy, with timeout)..."
    if command -v timeout >/dev/null 2>&1; then
      timeout 120 sudo umount -l "$mp" 2>/dev/null || timeout 120 sudo umount -f "$mp" 2>/dev/null || true
    else
      sudo umount -l "$mp" 2>/dev/null || sudo umount -f "$mp" 2>/dev/null || true
    fi
  fi
}

if ! $CHECK; then
  if ! dpkg-query -W -f='${Status}' nfs-common 2>/dev/null | grep -q "install ok installed"; then
    echo "Info    : Installing nfs-common package..."
    sudo apt update -qq
    sudo apt install -y nfs-common
  else
    $DEBUG && echo "Debug   : nfs-common already installed"
  fi
fi

if ! $CHECK; then
  sudo mkdir -p /mnt/spark
fi
if ! ensure_mode_contract "/mnt/spark"; then
  FAILURES=$((FAILURES + 1))
fi

for spec in "${MOUNT_POINTS[@]}"; do
  IFS=":" read -r mount_point export_path <<< "$spec"
  expected_mount="${NFS_SERVER}:${export_path}"

  if $IS_NFS_SERVER; then
    if [[ ! -d "$export_path" ]]; then
      if $CHECK; then
        echo "Check   : missing export directory $export_path"
        FAILURES=$((FAILURES + 1))
        continue
      fi
      echo "Info    : Creating export directory $export_path"
      sudo mkdir -p "$export_path"
    fi
    if ! ensure_mode_contract "$export_path"; then
      FAILURES=$((FAILURES + 1))
    fi

    if [[ -L "$mount_point" ]]; then
      link_target="$(readlink "$mount_point")"
      if [[ "$link_target" != "$export_path" ]]; then
        if $CHECK; then
          echo "Check   : symlink mismatch for $mount_point -> $link_target (expected $export_path)"
          FAILURES=$((FAILURES + 1))
          continue
        fi
        echo "Info    : Replacing symlink $mount_point -> $export_path"
        sudo rm -f "$mount_point"
        sudo ln -s "$export_path" "$mount_point"
      fi
    elif [[ -d "$mount_point" ]] && ! mountpoint -q "$mount_point"; then
      if $CHECK; then
        echo "Check   : $mount_point is plain directory; expected symlink to $export_path on NFS server"
        FAILURES=$((FAILURES + 1))
        continue
      fi
      echo "Info    : Replacing directory with symlink $mount_point -> $export_path"
      if [[ -n "$(ls -A "$mount_point" 2>/dev/null)" ]]; then
        sudo cp -a "$mount_point"/. "$export_path"/
      fi
      sudo rm -rf "$mount_point"
      sudo ln -s "$export_path" "$mount_point"
    elif [[ ! -e "$mount_point" ]]; then
      if $CHECK; then
        echo "Check   : missing symlink $mount_point -> $export_path"
        FAILURES=$((FAILURES + 1))
        continue
      fi
      echo "Info    : Creating symlink $mount_point -> $export_path"
      sudo ln -s "$export_path" "$mount_point"
    fi

    echo "Info    : Verified (server local): $mount_point -> $export_path"
    continue
  fi

  if ! $CHECK && [[ ! -d "$mount_point" ]]; then
    echo "Info    : Creating mount point directory: $mount_point"
    sudo mkdir -p "$mount_point"
  fi

  if mountpoint -q "$mount_point"; then
    current_mount="$(mount | awk '$3=="'"$mount_point"'" {print $1}' | head -1)"
    if [[ "$current_mount" != "$expected_mount" ]]; then
      if $CHECK; then
        echo "Check   : $mount_point mounted from $current_mount (expected $expected_mount)"
        FAILURES=$((FAILURES + 1))
        continue
      fi
      echo "Warning : $mount_point mounted from wrong source ($current_mount), remounting..."
      _nfs_umount "$mount_point"
      if command -v timeout >/dev/null 2>&1; then
        timeout 180 sudo mount -t nfs4 -o "$NFS_MOUNT_OPTS" "$expected_mount" "$mount_point"
      else
        sudo mount -t nfs4 -o "$NFS_MOUNT_OPTS" "$expected_mount" "$mount_point"
      fi
    fi
  else
    if $CHECK; then
      echo "Check   : $mount_point is not mounted (expected $expected_mount)"
      FAILURES=$((FAILURES + 1))
      continue
    fi
    echo "Info    : Mounting $expected_mount at $mount_point"
    if command -v timeout >/dev/null 2>&1; then
      timeout 180 sudo mount -t nfs4 -o "$NFS_MOUNT_OPTS" "$expected_mount" "$mount_point"
    else
      sudo mount -t nfs4 -o "$NFS_MOUNT_OPTS" "$expected_mount" "$mount_point"
    fi
  fi

  fstab_entry="${expected_mount} ${mount_point} nfs4 ${NFS_MOUNT_OPTS} 0 0"
  if ! grep -qE "[[:space:]]${mount_point}[[:space:]]" /etc/fstab; then
    if $CHECK; then
      echo "Check   : /etc/fstab missing entry for $mount_point"
      FAILURES=$((FAILURES + 1))
    else
      echo "Info    : Adding /etc/fstab entry for $mount_point"
      echo "$fstab_entry" | sudo tee -a /etc/fstab > /dev/null
    fi
  fi

  if [[ -d "$mount_point" ]] && [[ -r "$mount_point" ]]; then
    if ! ensure_mode_contract "$mount_point"; then
      FAILURES=$((FAILURES + 1))
    fi
    echo "Info    : Verified mount: $mount_point"
  else
    echo "Error   : Mount exists but is not accessible: $mount_point" >&2
    exit 1
  fi
done

if [[ "$FAILURES" -gt 0 ]]; then
  echo "Result  : Spark mounts check failed with $FAILURES issue(s)"
  exit 1
fi

echo "Result  : Spark mounts verified"
