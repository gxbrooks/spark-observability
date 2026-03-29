#!/bin/bash

# Enable SSH client access for a user by configuring their .ssh directory and SSH keys.
# This is for control-node SSH usage (Ansible, remote administration), not git globals.
# Appends a marked Host * IdentityFile block to ~/.ssh/config; myenv assert_git.sh prepends
# the github.com block — run assert_git before or after; both blocks are idempotent.

DEBUG=false
CHECK=false
USERNAME="$(whoami)"
PASSPHRASE=""
KEY_NAME="id_ed25519_ansible"

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d)
            DEBUG=true
            ;;
        --Check|-c)
            CHECK=true
            ;;
        --User|-u)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Error   : Missing value for --User|-u in $script_name."
                exit 1
            fi
            USERNAME="$1"
            ;;
        --Passphrase|-p|-N)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Error   : Missing value for --Passphrase|-p|-N in $script_name."
                exit 1
            fi
            PASSPHRASE="$1"
            ;;
        --KeyName|-k)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "Error   : Missing value for --KeyName|-k in $script_name."
                exit 1
            fi
            KEY_NAME="$1"
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name."
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--User|-u <username>] [--Passphrase|-p|-N <passphrase>] [--KeyName|-k <key_name>]"
            exit 1
            ;;
    esac
    shift
done

HOME_DIR="$(eval echo "~$USERNAME")"
SSH_DIR="$HOME_DIR/.ssh"
PRIVATE_KEY="$SSH_DIR/$KEY_NAME"
PUBLIC_KEY="${PRIVATE_KEY}.pub"
SSH_CONFIG="$SSH_DIR/config"
ANSIBLE_CFG_BEGIN="# BEGIN spark-observability ssh_client ansible"
ANSIBLE_CFG_END="# END spark-observability ssh_client ansible"

_ssh_config_strip_marked_block() {
    local file="$1" begin="$2" end="$3" out="$4"
    : >"$out"
    local skip=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$begin" ]]; then skip=1; continue; fi
        if [[ "$line" == "$end" ]]; then skip=0; continue; fi
        [[ $skip -eq 0 ]] && printf '%s\n' "$line" >>"$out"
    done <"$file"
}

ensure_ssh_config_ansible_identity() {
    # Host * + IdentityFile so non-interactive ssh/ansible uses id_ed25519_* without -i.
    # Kept after myenv's github.com block when both scripts have run (order: assert_git, then this).
    if $CHECK; then
        echo "Check   : Would append Host * IdentityFile ~/.ssh/$KEY_NAME to $SSH_CONFIG"
        return 0
    fi
    mkdir -p "$SSH_DIR"
    touch "$SSH_CONFIG"
    local rest
    rest="$(mktemp)"
    if grep -qF "$ANSIBLE_CFG_BEGIN" "$SSH_CONFIG" 2>/dev/null; then
        _ssh_config_strip_marked_block "$SSH_CONFIG" "$ANSIBLE_CFG_BEGIN" "$ANSIBLE_CFG_END" "$rest"
        mv "$rest" "$SSH_CONFIG"
    fi
    {
        [[ -s "$SSH_CONFIG" && "$(tail -c1 "$SSH_CONFIG" 2>/dev/null)" != $'\n' ]] && echo ""
        echo "$ANSIBLE_CFG_BEGIN"
        echo "Host *"
        echo "  IdentityFile ~/.ssh/$KEY_NAME"
        echo "$ANSIBLE_CFG_END"
    } >>"$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    chown "$USERNAME:$USERNAME" "$SSH_CONFIG"
    $DEBUG && echo "Debug   : Appended Ansible IdentityFile block to $SSH_CONFIG"
}

if [[ -d "$SSH_DIR" ]]; then
    $DEBUG && echo "Debug   : .ssh directory exists for user '$USERNAME'."
else
    if $CHECK; then
        echo "Check   : Would create .ssh directory for user '$USERNAME'."
    else
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        chown "$USERNAME:$USERNAME" "$SSH_DIR"
        echo "Result  : .ssh directory created for user '$USERNAME'."
    fi
fi

if [[ -f "$PRIVATE_KEY" && -f "$PUBLIC_KEY" ]]; then
    echo "Result  : SSH key pair exists for user '$USERNAME'."
else
    if $CHECK; then
        echo "Check   : Would generate SSH key pair for user '$USERNAME'."
    else
        if [[ -z "$PASSPHRASE" ]]; then
            echo "Error   : --Passphrase|-p|-N is required to generate a new SSH key."
            exit 1
        fi
        ssh-keygen -q -t ed25519 \
            -f "$PRIVATE_KEY" \
            -N "$PASSPHRASE" \
            -C "$USERNAME@$(hostname)" || {
            echo "Error   : Failed to generate SSH key pair for user '$USERNAME'."
            exit 1
        }
        chmod 600 "$PRIVATE_KEY"
        chmod 644 "$PUBLIC_KEY"
        chown "$USERNAME:$USERNAME" "$PRIVATE_KEY" "$PUBLIC_KEY"
        echo "Result  : SSH key pair generated for user '$USERNAME'."
    fi
fi

if [[ -f "$PRIVATE_KEY" && "$(stat -c "%a" "$PRIVATE_KEY")" -ne 600 ]]; then
    if $CHECK; then
        echo "Check   : Would fix private key permissions."
    else
        chmod 600 "$PRIVATE_KEY"
        chown "$USERNAME:$USERNAME" "$PRIVATE_KEY"
        echo "Result  : Private key permissions fixed."
    fi
fi

if [[ -f "$PUBLIC_KEY" && "$(stat -c "%a" "$PUBLIC_KEY")" -ne 644 ]]; then
    if $CHECK; then
        echo "Check   : Would fix public key permissions."
    else
        chmod 644 "$PUBLIC_KEY"
        chown "$USERNAME:$USERNAME" "$PUBLIC_KEY"
        echo "Result  : Public key permissions fixed."
    fi
fi

ensure_ssh_config_ansible_identity

if ! $CHECK; then
  echo "Info    : After a new login shell (or: source ~/.bashrc), keychain loads ~/.ssh/$KEY_NAME when present — see myenv/.bashrc (sourced via assert_bashrc.sh)."
  echo "Info    : Distribute the public key, e.g.: ssh-copy-id -i $PUBLIC_KEY user@host"
fi
if $DEBUG; then
    echo "Debug   : Public key path: $PUBLIC_KEY"
fi
