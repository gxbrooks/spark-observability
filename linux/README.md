# Linux Environment Setup and Configuration

This directory contains scripts and configuration for setting up and managing Linux environments in the Elastic-on-Spark project. It supports three main use cases: managed nodes (Ansible targets), devops clients (development machines), and environment configuration management.

## Table of Contents

- [Overview](#overview)
- [Main Entry Points](#main-entry-points)
- [Core Capabilities](#core-capabilities)
- [Environment Configuration System](#environment-configuration-system)
- [User Environment Integration](#user-environment-integration)
- [Directory Structure](#directory-structure)

## Overview

The `linux/` directory provides a comprehensive set of tools for:

1. **Node Setup**: Automated setup of managed nodes and devops clients
2. **Environment Management**: Centralized variable management and context-specific configuration generation
3. **User Environment Integration**: Seamless integration of project tools into user shell environments

## Main Entry Points

### 1. Managed Node Setup

For servers that will be managed by Ansible (e.g., Kubernetes workers):

```bash
./linux/assert_managed_node.sh --User ansible --Password <password> [--Debug]
```

**What it does:**
- Installs and configures SSH server
- Creates the `ansible` service account with passwordless sudo
- Sets up Python version management
- Configures Spark user and groups
- Prepares the node for Ansible automation

**See also:** `linux/docs/Initialize_Managed_Node.md` for complete setup guide

### 2. DevOps Client Setup

For development machines with full tooling:

```bash
./linux/assert_devops_client.sh -N <ssh_passphrase> [--Debug]
```

**What it does:**
- Installs development packages (jq, ansible-core, maven, etc.)
- Configures Java and Python environments
- Sets up SSH client with key generation
- Configures Git client for GitHub
- Creates Python virtual environment with PySpark
- Links project environment into user shell

**Required Options:**
- `-N <passphrase>`: Passphrase for SSH key generation (security requirement)

**Optional:**
- `-pyv <version>`: Override Python version (default from `variables.yaml`)
- `-jv <version>`: Override Java version
- `-sv <version>`: Override Spark version

## Core Capabilities

### Account Management

**`assert_service_account.sh`**
- Creates service accounts (e.g., `ansible`) with system-assigned UID/GID
- Adds accounts to required groups: `sudo`, `docker`, `users`, `sshusers`
- Configures SSH server access
- Sets up passwordless sudo

**`assert_spark_user.sh`**
- Creates `spark` user/group with fixed UID/GID (185/185)
- Required for Kubernetes pod file ownership consistency
- Adds current user and elastic-agent to spark group

**`assert_developer_user.sh`**
- Configures development user environment
- Sets up project permissions

### Version Management

**`assert_python_version.sh`**
- Ensures correct Python version is installed
- Manages multiple Python versions via `update-alternatives`
- Updates `/usr/bin/python3` symlink

**Python/Java versions** are defined in `variables.yaml` and generated into environment files.

### Package Management

**`assert_packages.sh`**
- Idempotent package installation
- Only installs missing packages
- Used by both managed node and devops client setup scripts

## Environment Configuration System

The project uses a centralized, data-driven configuration system based on:
- **`variables.yaml`**: Single source of truth for all variables
- **`contexts.yaml`**: Defines output contexts and formats
- **`generate_env.py`**: Transforms variables into context-specific files

This system generates configuration files in multiple formats (shell, YAML, TOML, Kubernetes ConfigMaps) to ensure consistency across Docker, Kubernetes, Ansible, and local development.

**For complete documentation** on the variable flow architecture, usage patterns, and troubleshooting, see:
- **`docs/Variable_Flow.md`** - Comprehensive guide to the configuration system

## User Environment Integration

The project provides seamless integration into user shell environments.

### `link_to_user_env.sh`

Links project configurations into user's bash environment:

```bash
./linux/link_to_user_env.sh [--Debug]
```

**What it does:**
- Adds `source ~/repos/elastic-on-spark/linux/.bash_aliases` to `~/.bash_aliases`
- Adds `source ~/repos/elastic-on-spark/linux/.bashrc` to `~/.bashrc`
- Makes project tools and aliases available in all shells

### `.bash_aliases`

Provides convenient command aliases for Docker Compose, Kubernetes, Git, and project-specific tools (HDFS, Elasticsearch APIs, etc.). See the file directly for the complete list of available aliases.

### `.bashrc`

Project bash environment setup:
- Starts ssh-agent for key management
- Configures keychain for SSH keys
- Adds project venv to PATH
- Platform detection (WSL vs native Linux)

## Usage Examples

### Setting Up a New Managed Node

```bash
# 1. Clone repository
git clone https://github.com/gxbrooks/elastic-on-spark.git ~/repos/elastic-on-spark
cd ~/repos/elastic-on-spark

# 2. Install SSH server
./ssh/install_ssh_service.sh --Debug

# 3. Create ansible service account and configure environment
./linux/assert_managed_node.sh --User ansible --Password <secure_password> --Debug

# 4. From control machine, copy SSH key
ssh-copy-id ansible@<hostname>

# 5. Test Ansible connectivity
ansible <hostname> -m ping
```

### Setting Up a Development Machine

```bash
# 1. Clone repository
git clone https://github.com/gxbrooks/elastic-on-spark.git ~/repos/elastic-on-spark
cd ~/repos/elastic-on-spark

# 2. Run devops client setup
./linux/assert_devops_client.sh -N <ssh_passphrase> --Debug

# 3. Activate virtual environment
source venv/bin/activate

# 4. Source Spark environment
source spark/spark_env.sh

# 5. Test Spark
python spark/apps/Chapter_03.py
```

### Updating Environment Variables

See `docs/Variable_Flow.md` for complete instructions on updating variables and regenerating configuration files.

Quick reference:
```bash
# 1. Edit variables.yaml
# 2. Regenerate: python3 linux/generate_env.py -f
# 3. Deploy changes as needed
```

## Key Design Principles

1. **Idempotency**: All scripts can be run multiple times safely
2. **System-Assigned IDs**: Service accounts get system-assigned UID/GID (except Spark which requires 185/185 for K8s)
3. **Separation of Concerns**: Clear distinction between managed nodes and devops clients
4. **Centralized Configuration**: Single source of truth in `variables.yaml`
5. **Consistency**: Same variables used across Docker, Kubernetes, Ansible, and local development

## Related Documentation

- **Variable Configuration**: `docs/Variable_Flow.md` - Complete guide to the centralized configuration system
- **Managed Node Setup**: `linux/docs/Initialize_Managed_Node.md` - Step-by-step guide for setting up Ansible targets
- **SSH Configuration**: `ssh/` directory - SSH server/client setup scripts
- **Spark Setup**: `spark/` directory - Spark-specific configuration
- **Ansible Automation**: `ansible/` directory - Playbooks and roles

## Notes

- **Python Version**: Default is 3.11, specified in `variables.yaml`
- **Java Version**: Default is 17, specified in `variables.yaml`
- **Spark Version**: Default is 4.0.1, specified in `variables.yaml`
- **Spark UID/GID**: Must be 185/185 to match Kubernetes pod securityContext
- **Ansible User**: System-assigned UID/GID for maximum compatibility

## Troubleshooting

**Environment files not generated:**
```bash
python3 linux/generate_env.py -f -v
```

**Python version mismatch:**
```bash
./linux/assert_python_version.sh --PythonVersion 3.11 --Debug
```

**Package installation issues:**
```bash
./linux/assert_packages.sh --Packages "jq ncat keychain" --Debug
```

For detailed troubleshooting of the variable configuration system, see `docs/Variable_Flow.md`.

