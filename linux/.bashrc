
echo "Setting up bash environment for Spark Observability..."
# bash environment configuration for Spark Observability
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LS_HOME=/usr/share/logstash
PATH=${PATH}:/home/gxbrooks/GitHub/elastic-on-spark/elasticsearch/bin

if ! grep -qi "microsoft\|wsl" /proc/version; then
    echo "Running on native Linux"
    # moved to wake on USB approach. See wake_on_usb.sh.
    # $dir/keep_awake.sh
else
    echo "Running on WSL"
    # start ssh-agent to manage SSH keys
    systemctl --user start ssh-agent
fi

# Setup ssh-agent entry for GitHub and ssh
# will prompt for passphrase if not already in ssh-agent
eval $(keychain --eval --agents ssh id_rsa id_ed25519)

# Add to ~/.bashrc
if ! pgrep -f ssh-agent > /dev/null; then
    eval "$(ssh-agent -s)"
    ssh-add # Add your keys here if you want them added automatically
fi

# Activate project virtual environment (only if not already activated)
if [ -z "$VIRTUAL_ENV" ]; then
    project_venv="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/venv"
    if [ -f "$project_venv/bin/activate" ]; then
        source "$project_venv/bin/activate"
        echo "Virtual environment activated: Python $(python --version 2>&1 | awk '{print $2}')"
    else
        echo "Warning: Virtual environment not found at $project_venv"
        # Fallback: Add to PATH if venv exists but no activate script
        if [[ ":$PATH:" != *":/home/gxbrooks/repos/elastic-on-spark/venv/bin:"* ]]; then
            export PATH="/home/gxbrooks/repos/elastic-on-spark/venv/bin:$PATH"
        fi
    fi
else
    echo "Virtual environment already active: $VIRTUAL_ENV"
fi

# Source Spark client environment variables
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$project_root/spark/spark_env.sh" ]; then
    source "$project_root/spark/spark_env.sh"
    # Set SPARK_MASTER_URL from external host/port
    export SPARK_MASTER_URL="spark://${SPARK_MASTER_EXTERNAL_HOST}:${SPARK_MASTER_EXTERNAL_PORT}"
fi

# Configure PySpark to use IPython for interactive sessions
export PYSPARK_DRIVER_PYTHON=ipython
export PYSPARK_DRIVER_PYTHON_OPTS=""
