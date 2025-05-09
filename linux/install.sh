#!/bin/bash

# this script augments the current user's environment for Spark Observability


# Set the 'dir' variable to the directory of this script
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure the user's .bash_aliases exists and contains the sourcing command
bash_aliases="$HOME/.bash_aliases"
spark_aliases_source="source $dir/.bash_aliases"

if [ ! -f "$bash_aliases" ]; then
    echo "$spark_aliases_source" > "$bash_aliases"
    echo "Started sourcing of Spark Observability .bash_aliases from user's bash_aliases file."
elif ! grep -Fxq "$spark_aliases_source" "$bash_aliases"; then
    echo "$spark_aliases_source" >> "$bash_aliases"
    echo "Added Spark Observability .bash_aliases sourcing to $bash_aliases."
fi

user_bashrc="$HOME/.bashrc"
spark_bashrc_source="source $dir/.bashrc"

if grep -Fxq "$spark_bashrc_source" "$user_bashrc"; then
    echo "Info: Spark Observability .bashrc is already being sourced in $user_bashrc."
else
    echo "$spark_bashrc_source" >> "$user_bashrc"
    echo "Result  : Added Spark Observability .bashrc sourcing to $user_bashrc."
fi

