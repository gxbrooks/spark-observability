#!/bin/bash
# Standard UIDs and GIDs for elastic-on-spark environment
# Source this file to get consistent IDs across all hosts
#
# Linux UID/GID allocation:
#   0         - root
#   1-99      - Static system users (reserved by distribution)
#   100-999   - Dynamic system users (services)
#   1000-59999 - Normal users (humans)

# Service Accounts (100-999 range)
SPARK_UID=185
SPARK_GID=185      # CRITICAL: Must match Kubernetes pod securityContext

# Note: elastic-agent UID/GID are managed by Elastic's package installer
# Typical values: UID=997, GID=984 (may vary by system)

# Normal Users (1000+ range)
ANSIBLE_UID=1001   # Automation service account
ANSIBLE_GID=1001

# Note: gxbrooks is typically the first user (UID=1000, GID=1000)
# This is created during OS installation and should not be modified

