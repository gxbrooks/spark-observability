# Initialize Managed Node (Lab1.lan)

This document provides the complete sequence to set up Lab1.lan as a new Kubernetes worker node for Spark operations, with proper user separation between development (`gxbrooks`) and operations (`ansible`).

## User Structure

- **`gxbrooks`**: Development user with full access to the repository and development tools
- **`ansible`**: Operations user for Ansible automation (passwordless sudo, SSH access)

## Complete Setup Sequence

### 1. On Lab1.lan (Initial Setup)

**Step 1: Install Git and Clone Repository**
```bash
# Install git if not already present
sudo apt update
sudo apt install -y git

# Clone the repository for gxbrooks user
sudo -u gxbrooks git clone https://github.com/gxbrooks/elastic-on-spark.git /home/gxbrooks/repos/elastic-on-spark
sudo chown -R gxbrooks:gxbrooks /home/gxbrooks/repos/elastic-on-spark

# Change to the repository directory
cd /home/gxbrooks/repos/elastic-on-spark
```

**Step 2: Install SSH Server and Configure**
```bash
# Run as root or with sudo from the repository directory
./ssh/install_ssh_service.sh --Debug
```

**Step 3: Create Operations User (ansible)**
```bash
# Create the ansible service account with passwordless sudo
./linux/initialize_managed_node.sh --User ansible --Password <secure_password> --Debug
```

**Step 4: Set Up SSH Access for Ansible**
```bash
# Ensure ansible user has proper SSH directory
sudo -u ansible mkdir -p /home/ansible/.ssh
sudo chmod 700 /home/ansible/.ssh
sudo chown ansible:ansible /home/ansible/.ssh
```

### 2. On Control Machine (Ansible Controller)

**Step 5: Copy SSH Keys to Operations User**
```bash
# Copy your SSH public key to the ansible user on Lab1
ssh-copy-id ansible@Lab1.lan
```

**Step 6: Test Ansible Connectivity**
```bash
# Test connectivity to the new node
ansible -i ansible/inventory.yml kubernetes_workers -m ping
```

**Step 7: Verify User Permissions**
```bash
# Verify ansible user has proper sudo access
ansible -i ansible/inventory.yml Lab1 -m shell -a "sudo -l"
```

### 3. Join to Kubernetes Cluster

**Step 8: Join Lab1 to Kubernetes Cluster**
```bash
# Run the Kubernetes setup playbook on the new worker
ansible-playbook -i ansible/inventory.yml ansible/playbooks/k8s/start_k8s.yml --limit Lab1
```

**Step 9: Verify Kubernetes Node Status**
```bash
# Check that Lab1 is now a Kubernetes worker node
kubectl get nodes
```

**Step 10: Deploy Spark Workers**
```bash
# Deploy Spark components (this will now include workers on Lab1)
ansible-playbook -i ansible/inventory.yml ansible/playbooks/spark/deploy_spark.yml
ansible-playbook -i ansible/inventory.yml ansible/playbooks/spark/start_spark.yml
```

## What Each Script Does

### `ssh/install_ssh_service.sh`
- Installs OpenSSH server
- Creates `sshusers` group
- Configures firewall rules (UFW)
- Sets up SSH configuration from `sshd_config.linux.cfg`
- Enables and starts SSH service

### `linux/initialize_managed_node.sh`
- Verifies SSH server is running (`ssh/assert_ssh_server.sh`)
- Creates and configures the ansible user (`ssh/assert_service_account.sh`)
- Sets up passwordless sudo for ansible user
- Creates `/mnt/c/Volumes` directory for cross-platform compatibility
- Adds ansible user to required groups (sudo, docker, users, sshusers)

### `ssh/assert_service_account.sh`
- Creates the ansible user account
- Sets up home directory with proper permissions
- Adds user to required groups: sudo, docker, users, sshusers
- Configures SSH access

## User Access Summary

| User | Purpose | Access Level | Repository Location |
|------|---------|--------------|-------------------|
| `gxbrooks` | Development | Full user access | `/home/gxbrooks/repos/elastic-on-spark` |
| `ansible` | Operations | Passwordless sudo, SSH | No repository access needed |

## Verification Commands

**Check SSH Service:**
```bash
sudo systemctl status ssh
sudo ufw status
```

**Check User Setup:**
```bash
id ansible
groups ansible
sudo -u ansible sudo -l
```

**Check Repository Access:**
```bash
ls -la /home/gxbrooks/repos/elastic-on-spark
```

**Test Ansible Connectivity:**
```bash
ansible -i ansible/inventory.yml Lab1 -m ping
ansible -i ansible/inventory.yml Lab1 -m shell -a "whoami"
```

## Troubleshooting

**If SSH connection fails:**
- Verify SSH service is running: `sudo systemctl status ssh`
- Check firewall: `sudo ufw status`
- Verify user exists: `id ansible`

**If Ansible fails:**
- Test SSH manually: `ssh ansible@Lab1.lan`
- Check sudo access: `ssh ansible@Lab1.lan "sudo -l"`
- Verify inventory: `ansible -i ansible/inventory.yml --list-hosts kubernetes_workers`

**If Kubernetes join fails:**
- Check network connectivity between Lab1 and Lab2
- Verify Lab2 (master) is accessible from Lab1
- Review Kubernetes logs: `journalctl -u kubelet`

## Next Steps

After successful setup:
1. Lab1.lan will be available as a Kubernetes worker node
2. Spark workers can be scheduled on Lab1.lan ++++++++++++++++
3. Development work can be done as `gxbrooks` user
4. Operations automation runs as `ansible` user
5. Both users can coexist without conflicts
