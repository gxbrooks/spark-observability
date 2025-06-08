#!/bin/bash

# Script to start Elastic Agent and then Docker containers for elastic-on-spark
# Assumes current directory is the project root (elastic-on-spark)

set -e

# Function to print error and exit
fail() {
  echo "[ERROR] $1" >&2
  exit 1
}

# 1. Check if any Docker Compose services are running
cd docker
if docker compose ps --services --filter "status=running" | grep -q .; then
  fail "Docker Compose services are already running. Please stop them before running this script."
fi
cd ..

# 2. Check if Elastic Agent is running (systemd service)
if systemctl is-active --quiet elastic-agent; then
  echo "Elastic Agent is running. Stopping it..."
  sudo systemctl stop elastic-agent
  sleep 2
fi

# 3. Start Elastic Agent
echo "Starting Elastic Agent..."
sudo systemctl start elastic-agent
sleep 3

# 4. Start Docker Compose stack (from docker directory)
echo "Starting Docker Compose services..."
cd docker
docker compose up -d
cd ..

# 5. Final status
if systemctl is-active --quiet elastic-agent; then
  echo "Elastic Agent is running."
else
  fail "Elastic Agent failed to start."
fi

echo "Docker Compose services status:"
cd docker
docker compose ps
cd ..

echo "All services started successfully."

