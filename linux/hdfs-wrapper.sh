#!/bin/bash
#
# HDFS Wrapper Script
# 
# This script provides seamless HDFS command access by setting up the proper
# environment variables and calling the hdfs command.
#
# Usage: hdfs <command> [options]
# Example: hdfs ls /
#          hdfs dfs -ls /
#          hdfs put localfile.txt /remote/path/

# Set the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source environment variables from generated files
ISPARK_ENV_FILE="${ROOT_DIR}/vars/contexts/ispark/ispark_env.sh"
if [ -f "${ISPARK_ENV_FILE}" ]; then
    source "${ISPARK_ENV_FILE}"
fi

# Set Hadoop environment variables from vars/variables.yaml
export HADOOP_NAMENODE="${HADOOP_NAMENODE:-10.101.125.84:9000}"
export HADOOP_CONF_DIR="${HADOOP_CONF_DIR:-/opt/hadoop/etc/hadoop}"
export HADOOP_HOME="${HADOOP_HOME:-/opt/hadoop}"
export HDFS_DEFAULT_FS="${HDFS_DEFAULT_FS:-hdfs://10.101.125.84:9000}"

# Debug output if needed
if [ "${DEBUG:-false}" = "true" ]; then
    echo "Debug: HADOOP_NAMENODE=$HADOOP_NAMENODE"
    echo "Debug: HADOOP_CONF_DIR=$HADOOP_CONF_DIR"
    echo "Debug: HADOOP_HOME=$HADOOP_HOME"
    echo "Debug: HDFS_DEFAULT_FS=$HDFS_DEFAULT_FS"
fi

# Call the actual hdfs command with all arguments
exec /usr/bin/hdfs "$@"
