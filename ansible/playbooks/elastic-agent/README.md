# Elastic Agent Deployment Strategy

This directory contains Ansible playbooks for deploying Elastic Agents on host systems (not in containers) for comprehensive monitoring of Spark applications and infrastructure.

## Architecture Overview

### Host-Based Deployment
Elastic Agents run directly on host systems to collect:
- **Spark Event Logs**: From NFS-mounted Spark History Server logs
- **System Logs**: Native system logs (syslog, auth, etc.)
- **Docker Logs**: Container logs from Docker daemon
- **Kubernetes Logs**: K8s API logs and pod logs

### Deployment Strategies

#### 1. Native Linux Deployment
- **Playbook**: `install_elastic_agent.yml` (Linux section)
- **Target**: `native` hosts (Lab1, Lab2)
- **Method**: Direct installation as systemd service
- **Log Collection**: Local filesystem + NFS mount for Spark logs

#### 2. Windows Deployment
- **Playbook**: `install_elastic_agent.yml` (Windows section)
- **Target**: `windows` hosts (GaryPC)
- **Method**: Windows service installation
- **Log Collection**: Local filesystem + NFS mount for Spark logs

## Key Benefits

### Host-Based Monitoring
- Direct access to all host-level logs and metrics
- No container isolation limitations
- Complete visibility into system resources

### Comprehensive Coverage
- Spark application logs via NFS
- System logs (syslog, auth, etc.)
- Docker container logs
- Kubernetes API and pod logs

### Simple Deployment
- Standard systemd service (Linux) or Windows service
- No Kubernetes complexity
- Easy configuration management

## Playbooks

### Core Playbooks
- `install_elastic_agent.yml` - Main deployment playbook for all environments
- `restart_elastic_agent.yml` - Restart agents with updated configuration
- `setup_nfs_directories.yml` - Setup NFS directory structure for Spark logs

## Configuration

### Log Collection Paths
- **Spark Events**: `/mnt/spark/events/spark-history/app-logs/*`
- **Spark Driver Logs**: `/mnt/spark/events/spark-history/driver-logs/*`
- **Spark Executor Logs**: `/mnt/spark/events/spark-history/executor-logs/*`
- **System Logs**: `/var/log/syslog`, `/var/log/auth.log`
- **Docker Logs**: `/var/lib/docker/containers/*/`

## Usage

### Deploy All Elastic Agents
```bash
ansible-playbook -i inventory.yml install_elastic_agent.yml
```

### Setup NFS Directories
```bash
ansible-playbook -i inventory.yml setup_nfs_directories.yml
```

### Restart Agents
```bash
ansible-playbook -i inventory.yml restart_elastic_agent.yml
```

## Monitoring

### Check Agent Status
```bash
# Native Linux
systemctl status elastic-agent
journalctl -u elastic-agent -f

# Windows
sc query "Elastic Agent"
```

### Verify Log Collection
```bash
# Check NFS directories
ls -la /mnt/spark/events/spark-history/

# Check agent logs
tail -f /var/log/elastic-agent/elastic-agent.log
```

## Troubleshooting

### Common Issues
1. **Permission Denied**: Check NFS mount permissions and directory ownership
2. **Agent Not Starting**: Verify configuration files and environment variables
3. **No Logs Collected**: Check log paths and file permissions

### Debug Commands
```bash
# Check NFS mounts
mount | grep nfs
df -h | grep nfs

# Check agent configuration
cat /opt/Elastic/Agent/elastic-agent.yml
```

## Best Practices

1. **Host-Based Deployment**: Always run Elastic Agent on the host, not in containers
2. **NFS Permissions**: Ensure proper NFS export permissions for Spark event logs
3. **Monitoring**: Set up alerts for agent failures and log collection issues
4. **Backup**: Regularly backup agent configurations and NFS data
5. **Security**: Use proper file permissions and network access controls
