
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
