# Docker Playbooks

This directory contains playbooks to manage Docker on native Linux hosts only. These playbooks explicitly exclude WSL instances, as WSL should use Docker from Windows Docker Desktop.

## Available Playbooks

- `install_docker.yml` - Installs Docker on native Linux machines
- `start_docker.yml` - Starts the Docker service and registry
- `stop_docker.yml` - Stops the Docker service
- `restart_docker.yml` - Restarts the Docker service
- `status_docker.yml` - Displays detailed Docker status information
- `diagnose_docker.yml` - Provides comprehensive diagnostics about Docker installation

## Usage

### Install Docker

```bash
ansible-playbook -i inventory.yml playbooks/docker/install_docker.yml
```

### Start Docker

```bash
ansible-playbook -i inventory.yml playbooks/docker/start_docker.yml
```

### Stop Docker

```bash
ansible-playbook -i inventory.yml playbooks/docker/stop_docker.yml
```

### Restart Docker

```bash
ansible-playbook -i inventory.yml playbooks/docker/restart_docker.yml
```

### Check Docker Status

```bash
ansible-playbook -i inventory.yml playbooks/docker/status_docker.yml
```

### Diagnose Docker Issues

```bash
ansible-playbook -i inventory.yml playbooks/docker/diagnose_docker.yml
```

## Notes

- These playbooks only target native Linux hosts (defined in the inventory as part of the `native` group)
- Windows hosts should use Docker Desktop
- WSL instances should use Docker from Windows Docker Desktop
- The playbooks include comprehensive error checking and diagnostic information
