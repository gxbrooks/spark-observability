#!/bin/bash

# Setup and configure the base utilities needed to support a Linux devops environment. 
# This includes SSH and Git client configuration and packages for json formmating (jq), key
# management,  and network debugging..

# Parse flags
CHECK=false
DEBUG=false
PASSPHRASE="" 
while [[ $# -gt 0 ]]; do
    echo "arg: $1"
    case $1 in
        --Check|-c) 
          CHECK=true 
          ;;
        --Debug|-d) 
          DEBUG=true 
          ;;
        -N|-p) 
          PASSPHRASE=$2
          shift
          ;;
        *) echo "Unknown parameter passed: $1"  >&2
          echo "Usage: $0 [--Check|-c] [--Debug|-c] [-N <passphrase>]" >&2
          exit 1
          ;;
    esac
    shift
done

if [[ -z "$PASSPHRASE" ]]; then
  echo "Error: Passphrase is mandatory. Use the -N option to specify it." >&2
  echo "Usage: $0 [--Check|-c] [--Debug|-c] [-N <passphrase>]"  >&2
  exit 1
fi

# Set the 'dir' variable to the directory of this script
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$dir/.." && pwd)"

if $DEBUG; then
  echo "Debug: root_dir = $root_dir"
  echo "Debug: PASSPHRASE = $PASSPHRASE"
  echo "Debug: CHECK = $CHECK"
fi

# Validate passphrase

if ! $CHECK; then
  sudo apt update && sudo apt upgrade -y
  sudo apt update && sudo apt  -y install jq ncat keychain bind9-dnsutils traceroute
fi

if ! $CHECK; then
  git config --global user.email "gxbrooks@gmail.com"
  git config --global user.name "Gary Brooks"
fi
# Function to append flags conditionally
append_flag() {
    local flag=$1
    local condition=$2
    [[ $condition == true ]] && echo "$flag"
}

$root_dir/ssh/install_ssh_client.sh \
  $(append_flag "--Check" "$CHECK") \
  $(append_flag "--Debug" "$DEBUG")

$root_dir/ssh/enable_user_for_git_client.sh \
    --User "$USER" \
    --Passphrase "$PASSPHRASE" \
    $(append_flag "--Check" "$CHECK") \
    $(append_flag "--Debug" "$DEBUG")

$root_dir/ssh/enable_user_for_ssh_client.sh \
    --User "$USER" \
    --Passphrase "$PASSPHRASE" \
    $(append_flag "--Check" "$CHECK")\
    $(append_flag "--Debug" "$DEBUG")

# link into the users bash environment
# Ensure the user's .bash_aliases exists and contains the sourcing command
bash_aliases="$HOME/.bash_aliases"
spark_aliases_source="source $dir/.bash_aliases"

$DEBUG && echo "Checking: linking ~/.bash_aliases to '$spark_aliases_source'."
if [ ! -f "$bash_aliases" ]; then
  if $CHECK; then
    echo "Result  : .bash_aliases does not exist for user '$USER'."
  else
    echo "$spark_aliases_source" > "$bash_aliases"
    echo "Result  : Started sourcing of Spark Observability .bash_aliases from user's bash_aliases file."
  fi
elif ! grep -Fxq "$spark_aliases_source" "$bash_aliases"; then
  if $CHECK; then
    echo "Result  : ~/.bash_aliases does not source $spark_aliases_source."
  else
    echo "$spark_aliases_source" >> "$bash_aliases"
    echo "Added .bash_aliases sourcing to $spark_aliases_source."
  fi
else 
    $DEBUG && echo "Result  : ~/.bash_aliases already sources $spark_aliases_source."
fi

user_bashrc="$HOME/.bashrc"
spark_bashrc_source="source $dir/.bashrc"

if grep -Fxq "$spark_bashrc_source" "$user_bashrc"; then
    echo "Result  : Spark Observability .bashrc is already being sourced in $user_bashrc."
elif $CHECK; then
    echo "Result  : ~/.bashrc does not source $spark_bashrc_source."
else
    echo "$spark_bashrc_source" >> "$user_bashrc"
    echo "Result  : Added Spark Observability .bashrc sourcing to $user_bashrc."
fi