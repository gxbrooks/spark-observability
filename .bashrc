echo "Setting up bash environment for Spark Observability..."
# bash environment configuration for Spark Observability
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LS_HOME=/usr/share/logstash

# Bootstrap: Ensure environment files are generated before sourcing them
# This must use system Python to avoid circular dependencies
# Only check if generate_env.sh exists (don't fail if vars/ doesn't exist)
if [ -f "$dir/vars/generate_env.sh" ]; then
    # Check if any required env files are missing or stale
    NEEDS_GEN=false
    for env_file in "$dir/vars/contexts/devops/devops_env.sh" \
                    "$dir/vars/contexts/spark-client/spark_env.sh"; do
        if [ ! -f "$env_file" ] || \
           [ "$dir/vars/variables.yaml" -nt "$env_file" ] 2>/dev/null || \
           [ "$dir/vars/contexts.yaml" -nt "$env_file" ] 2>/dev/null; then
            NEEDS_GEN=true
            break
        fi
    done
    
    if [ "$NEEDS_GEN" = "true" ]; then
        # Generate missing/stale environment files (quietly, don't fail if it errors)
        "$dir/vars/generate_env.sh" devops spark-client >/dev/null 2>&1 || true
    fi
fi

# Add ops/observability/elasticsearch/bin to PATH for esapi and kapi commands
if [[ ":$PATH:" != *":${dir}/ops/observability/elasticsearch/bin:"* ]]; then
    export PATH="${dir}/ops/observability/elasticsearch/bin:$PATH"
fi

if ! grep -qi "microsoft\|wsl" /proc/version; then
    echo "Running on native Linux"
    # moved to wake on USB approach. See wake_on_usb.sh.
    # $dir/keep_awake.sh
else
    echo "Running on WSL"
    # start ssh-agent to manage SSH keys
    systemctl --user start ssh-agent
fi

# ~/.bashrc

# Use keychain to manage SSH keys
eval $(keychain --quiet --eval id_ed25519 id_rsa)


# Activate project virtual environment (only if not already activated)
if [ -z "$VIRTUAL_ENV" ]; then
    project_venv="${dir}/venv"
    if [ -f "$project_venv/bin/activate" ]; then
        source "$project_venv/bin/activate"
        echo "Virtual environment activated: Python $(python --version 2>&1 | awk '{print $2}')"
    else
        echo "Warning: Virtual environment not found at $project_venv"
        # Fallback: Add to PATH if venv exists but no activate script
        if [[ ":$PATH:" != *":${dir}/venv/bin:"* ]]; then
            export PATH="${dir}/venv/bin:$PATH"
        fi
    fi
else
    echo "Virtual environment already active: $VIRTUAL_ENV"
fi

# Source devops environment variables (Python version, OTEL config, etc.)
project_root="${dir}"
devops_env_file="$project_root/vars/contexts/devops/devops_env.sh"

if [ -f "$devops_env_file" ]; then
    source "$devops_env_file"
else
    echo "Warning: devops_env.sh not found. Run: bash vars/generate_env.sh devops"
fi

# Set SPARK_LOCAL_IP to suppress hostname resolution warnings
# This prevents "Your hostname, Lab2, resolves to a loopback address" warning
export SPARK_LOCAL_IP="${SPARK_LOCAL_IP:-192.168.1.48}"

# Generate spark-defaults.conf from template on each login
# This ensures configuration stays in sync with variables.yaml
spark_defaults_generator="$project_root/linux/generate_spark_defaults.sh"
if [ -f "$spark_defaults_generator" ]; then
    # Run quietly - only show errors
    if ! "$spark_defaults_generator" > /dev/null 2>&1; then
        echo "Warning: Failed to generate spark-defaults.conf (run manually if needed)"
    fi
fi

# Source Spark client environment variables
if [ -f "$project_root/vars/contexts/spark-client/spark_env.sh" ]; then
    source "$project_root/vars/contexts/spark-client/spark_env.sh"
    # Set SPARK_MASTER_URL from host/port
    export SPARK_MASTER_URL="spark://${SPARK_MASTER_HOST}:${SPARK_MASTER_PORT}"
fi

# Configure PySpark to use IPython for interactive sessions
export PYSPARK_DRIVER_PYTHON=ipython
export PYSPARK_DRIVER_PYTHON_OPTS=""
