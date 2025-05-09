
# bash environment configuration for Spark Observability
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

$dir/keep_awake.sh

LS_HOME=/usr/share/logstash
PATH=${PATH}:/home/gxbrooks/GitHub/elastic-on-spark/elasticsearch/bin

# Setup ssh-agent entry for GitHub 
# will prompt for passphrase if not already in ssh-agent
eval $(keychain --eval --quiet id_ed25519)
# will prompt for passphrase if not already in ssh-agent
# Setup ssh-agent entry for SSH
eval $(keychain --eval --quiet id_rsa)

