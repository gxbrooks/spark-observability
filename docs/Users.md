# User and Group Management

## Overview

This document defines the standard users, groups, and their roles across all hosts in the elastic-on-spark environment. Following Linux best practices for UID/GID allocation ensures consistency and avoids conflicts.

## Linux UID/GID Ranges

| Range | Purpose | Our Usage |
|-------|---------|-----------|
| 0 | root superuser | System administration |
| 1-99 | Static system users | Reserved by distributions |
| 100-999 | Dynamic system users | Service accounts (spark, elastic-agent) |
| 1000-59999 | Normal users | Human users (gxbrooks, ansible) |
| 60000-65535 | Reserved | Not used |

## Standard Users and Groups

### Service Accounts (System Range: 100-999)

#### spark (UID/GID: 185)

**Role**: Spark cluster service account

**Purpose**: 
- Run Spark daemons (master, worker, history server)
- Own Spark application files and logs
- Kubernetes pods run with this UID/GID

**Home Directory**: `/home/spark` (created by Kubernetes hostPath mounts)

**Group Memberships**:
- Primary group: `spark` (185)

**Members of spark group**:
- `gxbrooks` - Can access Spark files and logs
- `elastic-agent` - Can read Spark logs for monitoring

**Shell**: `/bin/bash`

**Created By**: `linux/assert_spark_user.sh`

**Notes**: 
- UID/GID 185 is REQUIRED to match Kubernetes pod security context
- All Spark files written by pods will have GID 185
- Any user needing to read Spark files must be in the spark group

---

#### elastic-agent (UID: 997, GID: 984)

**Role**: Elastic Agent monitoring service

**Purpose**:
- Collect system metrics, logs, and events
- Forward data to Elasticsearch
- Monitor Spark application logs and metrics

**Home Directory**: `/opt/Elastic/Agent`

**Group Memberships**:
- Primary group: `elastic-agent` (984)
- Secondary groups: `gxbrooks` (1000), `spark` (185)

**Members of elastic-agent group**:
- `ansible` - Service management
- `gxbrooks` - Administration and debugging

**Shell**: `/usr/sbin/nologin` (service account, no interactive login)

**Created By**: Elastic Agent installation package

**Notes**:
- Must be in `spark` group (185) to read Spark application logs
- Group membership allows access to `/mnt/spark/logs/*` files
- Systemd service runs as this user

---

### Human Users (Normal Range: 1000+)

#### gxbrooks (UID/GID: 1000)

**Role**: Primary system administrator and developer

**Purpose**:
- System administration
- Development and testing
- Spark application development and execution
- Observability stack management

**Home Directory**: `/home/gxbrooks`

**Group Memberships**:
- Primary group: `gxbrooks` (1000)
- Secondary groups: 
  - `adm` (4) - View logs
  - `sudo` (27) - Administrative access
  - `docker` (125) - Docker management
  - `kubernetes` (1003/1004) - Kubernetes access
  - `spark` (185) - Spark file access
  - `elastic-agent` (984) - Elastic Agent administration

**Shell**: `/bin/bash`

**Created By**: System installation (first user)

**Notes**:
- Primary administrative account
- Has sudo privileges
- Member of spark group for development access

---

#### ansible (UID: 1001, GID: 1001/1002)

**Role**: Automation service account

**Purpose**:
- Ansible playbook execution
- Remote system configuration
- Service deployment and management

**Home Directory**: `/home/ansible`

**Group Memberships**:
- Primary group: `ansible` (1001 on Lab2, 1002 on Lab1)
- Secondary groups:
  - `sudo` (27) - Administrative access (passwordless)
  - `docker` (125/124) - Docker management
  - `kubernetes` (1003/1004) - Kubernetes access
  - `sshusers` (1001/1003) - SSH access
  - `elastic-agent` (984) - Service management

**Shell**: `/bin/bash`

**Created By**: `linux/assert_service_account.sh` (via `assert_managed_node.sh`)

**Notes**:
- Configured for SSH key-based authentication
- Passwordless sudo access
- **Inconsistency Alert**: GID differs between hosts (1001 vs 1002) - should be standardized

---

## Group Membership Matrix

| User | Primary Group | Secondary Groups |
|------|--------------|------------------|
| **spark** | spark (185) | *(none)* |
| **elastic-agent** | elastic-agent (984) | gxbrooks (1000), spark (185) |
| **gxbrooks** | gxbrooks (1000) | adm, sudo, docker, kubernetes, spark (185), elastic-agent (984) |
| **ansible** | ansible (1001/1002) | sudo, docker, kubernetes, sshusers, elastic-agent (984) |

## Group Purpose and Access

| Group | GID | Purpose | Key Paths |
|-------|-----|---------|-----------|
| **spark** | 185 | Spark application files and logs | `/mnt/spark/logs/*`, `/mnt/spark/events/*` |
| **elastic-agent** | 984 | Elastic Agent configuration and administration | `/opt/Elastic/Agent/*`, `/var/log/elastic-agent/*` |
| **gxbrooks** | 1000 | Personal files for gxbrooks user | `/home/gxbrooks/*` |
| **ansible** | 1001/1002 | Automation files for ansible user | `/home/ansible/*` |

## Automated User Setup

### Managed Nodes (Server Hosts)

**Script**: `linux/assert_managed_node.sh`

**Creates/Configures**:
1. `ansible` user (service account)
2. `spark` user and group (UID/GID 185)
3. SSH server configuration
4. Python environment

**Usage**:
```bash
./linux/assert_managed_node.sh \
  --User ansible \
  --Password <password> \
  -pyv 3.11 \
  -jv 17
```

**Ensures**:
- spark group has GID 185
- Current user added to spark group
- elastic-agent user added to spark group (if exists)

---

### DevOps Clients (Developer Workstations)

**Script**: `linux/assert_devops_client.sh`

**Creates/Configures**:
1. `spark` user and group (UID/GID 185)
2. SSH client configuration
3. Git configuration
4. Python virtual environment with PySpark
5. Development tools (jq, ansible, maven)

**Usage**:
```bash
./linux/assert_devops_client.sh \
  -N <ssh-passphrase> \
  -pyv 3.11 \
  -jv 17 \
  -sv 4.0.1
```

**Ensures**:
- spark group has GID 185
- Current user added to spark group
- PySpark version matches cluster Spark version

---

## Best Practices

### UID/GID Assignment

1. **System Service Accounts (100-999)**:
   - Use static UIDs/GIDs for services that need to match across hosts
   - Example: `spark:185` must be consistent for Kubernetes compatibility

2. **Human Users (1000+)**:
   - First user typically gets UID 1000
   - Subsequent users get incremental UIDs
   - Consider centralized user management (LDAP/AD) for large deployments

3. **Group Membership**:
   - Add users to groups rather than changing file permissions
   - Service accounts should have minimal group memberships
   - Human users can have broader group access for administration

### Consistency Requirements

1. **Critical Consistency** (Must match across ALL hosts):
   - `spark` UID/GID: **185** (Kubernetes requirement)
   - `elastic-agent` UID/GID: Should be consistent (currently 997/984)

2. **Recommended Consistency** (Should match for simplicity):
   - `ansible` UID/GID: Currently differs (1001 vs 1002) - consider standardizing
   - `gxbrooks` UID/GID: Currently matches (1000) - maintain this

3. **Flexible** (Can differ between hosts):
   - Dynamic system accounts
   - Transient service accounts

### Security Considerations

1. **Service Accounts**:
   - Use `/usr/sbin/nologin` shell for non-interactive accounts
   - Limit sudo access to specific commands
   - Regular accounts should not have default passwords

2. **Group Access**:
   - Grant read-only access via group membership
   - Avoid world-readable files in `/mnt/spark/logs/`
   - Use umask 0027 for service accounts (group-readable, not world-readable)

3. **SSH Access**:
   - Key-based authentication only
   - Restrict ansible user to specific source IPs if possible
   - Regularly rotate service account credentials

## Verification Commands

### Check User Configuration
```bash
# List all relevant users
getent passwd spark elastic-agent gxbrooks ansible

# List all relevant groups
getent group spark elastic-agent gxbrooks ansible

# Show user's group memberships
id gxbrooks
id ansible
id elastic-agent
```

### Verify Spark File Access
```bash
# Test if elastic-agent can read Spark logs
sudo -u elastic-agent test -r /mnt/spark/logs/spark-master-0/spark-app.log && echo "OK" || echo "FAILED"

# Test if gxbrooks can read Spark logs
test -r /mnt/spark/logs/spark-master-0/spark-app.log && echo "OK" || echo "FAILED"

# Check file permissions
ls -la /mnt/spark/logs/spark-*/spark-app.log | head -5
```

### Verify Group Consistency
```bash
# Run on all managed nodes
ansible all -i ansible/inventory.yml -m shell -a "getent group spark"

# Check for GID consistency
ansible all -i ansible/inventory.yml -m shell -a "getent group spark | cut -d: -f3"
```

## Troubleshooting

### Symptom: elastic-agent cannot read Spark logs

**Check**:
```bash
sudo -u elastic-agent ls -la /mnt/spark/logs/spark-master-0/
```

**Fix**:
```bash
# Add elastic-agent to spark group
sudo usermod -a -G spark elastic-agent

# Restart elastic-agent service
sudo systemctl restart elastic-agent.service
```

---

### Symptom: Spark group has wrong GID

**Check**:
```bash
getent group spark
# Should show: spark:x:185:...
```

**Fix**:
```bash
# Change spark group GID to 185
sudo groupmod -g 185 spark

# Add users back to spark group
sudo usermod -a -G spark elastic-agent
sudo usermod -a -G spark gxbrooks
```

---

### Symptom: Files show numeric GID instead of group name

**Example**: `spark:185` instead of `spark:spark`

**Cause**: Kubernetes containers use GID 185, but host doesn't have a group with that GID

**Fix**:
```bash
# Ensure spark group exists with GID 185
./linux/assert_spark_user.sh
```

---

## Related Files

- `linux/assert_spark_user.sh` - Creates spark user/group, enforces GID 185
- `linux/assert_service_account.sh` - Creates ansible service account
- `linux/assert_managed_node.sh` - Complete managed node setup
- `linux/assert_devops_client.sh` - Complete devops client setup
- `ansible/playbooks/elastic-agent/install.yml` - Elastic Agent deployment
- `variables.yaml` - Central configuration for versions and settings

