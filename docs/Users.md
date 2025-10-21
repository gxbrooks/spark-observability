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

## Automated User Setup with ID Consistency

### Standard IDs (Defined in `linux/standard_ids.sh`)

```bash
# Service Accounts (100-999 range)
SPARK_UID=185
SPARK_GID=185      # CRITICAL: Must match Kubernetes

# Normal Users (1000+ range)  
ANSIBLE_UID=1001
ANSIBLE_GID=1001
```

These IDs are automatically enforced by the assert_* scripts.

---

### Managed Nodes (Server Hosts)

**Script**: `linux/assert_managed_node.sh`

**Creates/Configures**:
1. `ansible` user with UID/GID 1001 (service account)
2. `spark` user and group with UID/GID 185
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

**Automatic ID Enforcement**:
- ✅ Verifies spark group is GID 185 (fixes if wrong)
- ✅ Verifies ansible user is UID/GID 1001 (fixes if wrong)
- ✅ Adds current user to spark group
- ✅ Adds elastic-agent to spark group (if exists)
- ✅ Creates users with standard IDs on new hosts
- ✅ Fixes ID mismatches on existing hosts

---

### DevOps Clients (Developer Workstations)

**Script**: `linux/assert_devops_client.sh`

**Creates/Configures**:
1. `spark` user and group with UID/GID 185
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

**Automatic ID Enforcement**:
- ✅ Verifies spark group is GID 185 (fixes if wrong)
- ✅ Adds current user to spark group
- ✅ Adds elastic-agent to spark group (if exists)
- ✅ Verifies PySpark matches cluster Spark version

---

### Verifying ID Consistency

**Script**: `linux/verify_id_consistency.sh`

**Purpose**: Check that all hosts have consistent UIDs/GIDs

**Usage**:
```bash
./linux/verify_id_consistency.sh
```

**Checks**:
- ✓ spark GID is 185 on all hosts
- ✓ ansible UID/GID is 1001 on all hosts (recommended)
- ✓ elastic-agent is member of spark group on all hosts

**Example Output**:
```
============================================
UID/GID Consistency Verification
============================================

Checking Lab1...
  ✓ spark GID: 185 (correct)
  ✓ ansible UID: 1001 (correct)
  ✓ ansible GID: 1001 (correct)
  ✓ elastic-agent in spark group

Checking Lab2...
  ✓ spark GID: 185 (correct)
  ✓ ansible UID: 1001 (correct)
  ✓ ansible GID: 1001 (correct)
  ✓ elastic-agent in spark group

============================================
✓ All critical IDs are consistent
============================================
```

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

## Setting Up a New Host

### Process

1. **Run assert script on the new host**:
   ```bash
   # For managed nodes (servers):
   ./linux/assert_managed_node.sh --User ansible --Password <pwd> -pyv 3.11 -jv 17
   
   # For devops clients (developers):
   ./linux/assert_devops_client.sh -N <passphrase> -pyv 3.11 -jv 17 -sv 4.0.1
   ```

2. **Verify ID consistency across all hosts**:
   ```bash
   ./linux/verify_id_consistency.sh
   ```

3. **If inconsistencies detected**:
   - The verification script will report which IDs are wrong
   - Re-run the appropriate assert_* script on the problematic host
   - The script will automatically fix the IDs

### How ID Consistency is Enforced

**Automatic Detection and Correction**:

1. **`linux/standard_ids.sh`**: Defines standard UIDs/GIDs
   - Sourced by all assert_* scripts
   - Single source of truth for IDs

2. **`assert_spark_user.sh`**:
   - Checks if spark group exists
   - If GID is wrong → Changes it to 185
   - Adds elastic-agent and current user to spark group

3. **`assert_service_account.sh`** (via `assert_managed_node.sh`):
   - Checks if ansible user exists
   - If UID/GID is wrong → Changes to 1001/1001
   - Creates with correct IDs if new

4. **`verify_id_consistency.sh`**:
   - Runs checks across all hosts in inventory
   - Reports any inconsistencies
   - Suggests remediation steps

### Example: Adding Lab3 as New Host

```bash
# 1. On Lab3, clone repository
git clone https://github.com/gxbrooks/elastic-on-spark.git
cd elastic-on-spark

# 2. Run managed node setup
./linux/assert_managed_node.sh --User ansible --Password <secure-pwd> -pyv 3.11 -jv 17

# This automatically:
# - Creates ansible user with UID/GID 1001
# - Creates spark user/group with UID/GID 185
# - Adds gxbrooks to spark group
# - Adds elastic-agent to spark group (if exists)

# 3. From control machine, verify consistency
./linux/verify_id_consistency.sh

# 4. Deploy Kubernetes and Spark
ansible-playbook -i ansible/inventory.yml ansible/playbooks/k8s/start_k8s.yml --limit Lab3
ansible-playbook -i ansible/inventory.yml ansible/playbooks/spark/deploy.yml --limit Lab3
```

### Example: Fixing Existing Host with Wrong IDs

```bash
# Scenario: Lab1 has spark GID 1004 instead of 185

# 1. Run verify script to detect
./linux/verify_id_consistency.sh
# Output: ✗ spark GID: 1004 (expected 185)

# 2. Fix by running assert script on Lab1
ansible Lab1 -i ansible/inventory.yml -m shell -a "cd /home/gxbrooks/repos/elastic-on-spark && ./linux/assert_spark_user.sh"

# The script will:
# - Detect GID mismatch (1004 vs 185)
# - Change spark group to GID 185
# - Re-add all users to spark group
# - Verify elastic-agent has access

# 3. Verify fix
./linux/verify_id_consistency.sh
# Output: ✓ spark GID: 185 (correct)

# 4. Restart elastic-agent to pick up new group membership
ansible Lab1 -i ansible/inventory.yml -m shell -a "sudo systemctl restart elastic-agent.service" -b
```

---

## Related Files

- `linux/standard_ids.sh` - **NEW**: Defines standard UIDs/GIDs for all scripts
- `linux/verify_id_consistency.sh` - **NEW**: Verifies IDs across all hosts
- `linux/assert_spark_user.sh` - Creates spark user/group, enforces GID 185
- `linux/assert_service_account.sh` - Creates service accounts with UID/GID enforcement
- `ssh/assert_service_account.sh` - Low-level user creation with UID/GID support
- `ssh/assert_group.sh` - Group creation with GID support
- `linux/assert_managed_node.sh` - Complete managed node setup
- `linux/assert_devops_client.sh` - Complete devops client setup
- `ansible/playbooks/elastic-agent/install.yml` - Elastic Agent deployment
- `variables.yaml` - Central configuration for versions and settings

