#!/bin/bash

# One-time linker: append sourcing of this repo's .bash_aliases and .bashrc to the user's
# ~/.bash_aliases and ~/.bashrc. Per-login SSH keys (including id_ed25519_ansible for Ansible)
# are loaded by keychain from the repo .bashrc — not from this script (which runs once).

# Parse flags
CHECK=false
DEBUG=false

while [[ $# -gt 0 ]]; do
    echo "arg: $1"
    case $1 in
        --Check|-c) 
          CHECK=true 
          ;;
        --Debug|-d) 
          DEBUG=true 
          ;;
        *) echo "Unknown parameter passed: $1"  >&2
          echo "Usage: $0 [--Check|-c] [--Debug|-d]" >&2
          exit 1
          ;;
    esac
    shift
done

# Set the 'dir' variable to the project root (parent of linux directory)
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
