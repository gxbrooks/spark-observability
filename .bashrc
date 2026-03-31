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
    for env_file in "$dir/vars/contexts/devops_env.sh" \
                    "$dir/vars/contexts/spark_client_env.sh"; do
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

# Load SSH keys into ssh-agent (keychain: linux/assert_client_node.sh / myenv assert_packages).
# Only id_ed25519_<purpose> keys. id_ed25519_github → GitHub; id_ed25519_ansible → Ansible, Lab, GaryPC, etc.
_keychain_keys=()
for _k in id_ed25519_github id_ed25519_ansible; do
  [[ -f "$HOME/.ssh/$_k" ]] && _keychain_keys+=("$_k")
done
if ((${#_keychain_keys[@]})); then
  command -v keychain >/dev/null 2>&1 && eval "$(keychain --quiet --eval "${_keychain_keys[@]}")"
fi
unset _k _keychain_keys

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
devops_env_file="$project_root/vars/contexts/devops_env.sh"

if [ -f "$devops_env_file" ]; then
    source "$devops_env_file"
else
    echo "Warning: devops_env.sh not found. Run: bash vars/generate_env.sh devops"
fi

# Bind address for Spark client mode.
# If SPARK_LOCAL_IP is unset OR points to an IP not on this host, reset it to this host's primary IPv4.
_spark_lip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')"
if [[ -n "${_spark_lip:-}" ]]; then
    _host_ips=" $(hostname -I 2>/dev/null) "
    if [[ -z "${SPARK_LOCAL_IP:-}" ]] || [[ "$_host_ips" != *" ${SPARK_LOCAL_IP} "* ]]; then
        export SPARK_LOCAL_IP="$_spark_lip"
    fi
    unset _host_ips
fi
unset _spark_lip

# Source Spark client environment variables (before generating spark-defaults.conf)
if [ -f "$project_root/vars/contexts/spark_client_env.sh" ]; then
    # shellcheck disable=SC1091
    source "$project_root/vars/contexts/spark_client_env.sh"
    # Point Spark client-mode driver to the current machine with a routable DNS name.
    # If hostname is short (e.g. "Lab3"), append ".lan" so cluster workers can resolve it.
    _spark_host="$(hostname -f 2>/dev/null || hostname)"
    if [[ "$_spark_host" != *.* ]]; then
        _spark_host="${_spark_host}.lan"
    fi
    export SPARK_DRIVER_HOST="$_spark_host"
    unset _spark_host
    # Set SPARK_MASTER_URL from host/port
    export SPARK_MASTER_URL="spark://${SPARK_MASTER_HOST}:${SPARK_MASTER_PORT}"
fi

# Sync ~/.kube/config from control plane when admin.conf changes (KUBERNETES_API_SERVER / _URL from env above).
if [ -f "$project_root/linux/sync_devops_kubeconfig.sh" ]; then
    # shellcheck source=linux/sync_devops_kubeconfig.sh
    source "$project_root/linux/sync_devops_kubeconfig.sh"
    sync_devops_kubeconfig 2>/dev/null || true
fi

# Generate spark-defaults.conf from template on each login
# This ensures configuration stays in sync with variables.yaml
# Note: generate_spark_defaults.sh sources spark_client_env.sh if variables aren't already set
spark_defaults_generator="$project_root/linux/generate_spark_defaults.sh"
if [ -f "$spark_defaults_generator" ]; then
    # Run quietly - only show errors
    if ! "$spark_defaults_generator" > /dev/null 2>&1; then
        echo "Warning: Failed to generate spark-defaults.conf (run manually if needed)"
    fi
fi

# Do not set PYSPARK_DRIVER_PYTHON=ipython globally — it breaks batch chapter scripts run as `python ...`.
# IPython is set in spark/ispark/launch_ipython.sh only.
if [[ "${PYSPARK_DRIVER_PYTHON:-}" == "ipython" ]]; then
    export PYSPARK_DRIVER_PYTHON="${PYSPARK_PYTHON:-python3}"
    unset PYSPARK_DRIVER_PYTHON_OPTS
fi
