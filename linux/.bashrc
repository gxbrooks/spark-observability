
echo "Setting up bash environment for Spark Observability..."
# bash environment configuration for Spark Observability
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LS_HOME=/usr/share/logstash
PATH=${PATH}:/home/gxbrooks/GitHub/elastic-on-spark/elasticsearch/bin

if ! grep -qi "microsoft\|wsl" /proc/version; then
    echo "Running on native Linux"
    $dir/keep_awake.sh
else
    echo "Running on WSL"
    systemctl --user start ssh-agent
fi

# Setup ssh-agent entry for GitHub and ssh
# will prompt for passphrase if not already in ssh-agent
eval $(keychain --eval --agents ssh id_rsa id_ed25519)


