#!/bin/bash
# Update Elastic Agent configuration to monitor local event logs
sudo sed -i 's|/mnt/spark/events/app-\*|/tmp/spark/events/app-*|g' /opt/Elastic/Agent/elastic-agent.yml
sudo systemctl restart elastic-agent
echo "Elastic Agent configuration updated and restarted"
