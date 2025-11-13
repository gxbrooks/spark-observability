# Observability Platform Playbooks

This directory contains the consolidated playbooks for managing the observability platform (Elasticsearch, Kibana, Grafana, Logstash).

## Playbook Structure

### Core Playbooks (Top Level)
- **`install.yml`** - Complete installation (files + services)
- **`start.yml`** - Start existing services
- **`stop.yml`** - Stop services
- **`uninstall.yml`** - Remove everything
- **`status.yml`** - Check service status

### Usage Examples

```bash
# Complete installation (first time)
ansible-playbook -i inventory.yml playbooks/observability/install.yml

# Start services (after installation)
ansible-playbook -i inventory.yml playbooks/observability/start.yml

# Stop services
ansible-playbook -i inventory.yml playbooks/observability/stop.yml

# Check status
ansible-playbook -i inventory.yml playbooks/observability/status.yml

# Complete removal
ansible-playbook -i inventory.yml playbooks/observability/uninstall.yml
```

## Host Support

### Linux/WSL Hosts
- Full Docker Compose support
- Service health checks
- Container status monitoring
- Elasticsearch/Kibana API checks

### Windows Hosts
- Docker Desktop service management
- Conditional Windows-specific tasks
- Service status monitoring

## Features

### Cross-Platform Support
- Automatic OS detection
- Conditional task execution
- Windows service management
- Linux Docker management

### Service Management
- Docker container lifecycle
- Network and volume cleanup
- Health checks for all services
- Graceful startup/shutdown

### Data Persistence
- Docker volumes for data persistence
- Configuration file management
- Certificate distribution
- Log directory setup

## Service URLs

After installation, services are accessible at:

- **Elasticsearch**: https://GaryPC.local:9200
- **Kibana**: http://GaryPC.local:5601
- **Grafana**: http://GaryPC.local:3000
- **Logstash**: GaryPC.local:5050

## Credentials

- **Elasticsearch/Kibana**: elastic / myElastic2025
- **Grafana**: Check `.env` file for admin password

## Troubleshooting

### Common Issues

1. **Docker not available**: Ensure Docker Desktop is installed and running
2. **Port conflicts**: Check if ports 9200, 5601, 3000, 5050 are available
3. **Permission issues**: Ensure ansible user has Docker access
4. **Service startup time**: Services may take 2-3 minutes to fully start

### Debug Commands

```bash
# Check Docker status
docker ps -a

# Check service logs
docker-compose logs

# Check specific service
docker-compose logs elasticsearch
docker-compose logs kibana
```

## Migration from Old Playbooks

The following old playbooks have been consolidated:

- `deploy_observability.yml` → `install.yml`
- `setup_observability_repo.yml` → `install.yml`
- `start_observability.yml` → `start.yml`
- `stop_observability.yml` → `stop.yml`
- `shutdown_observability.yml` → `stop.yml`
- `status_observability.yml` → `status.yml`
- `uninstall_observability.yml` → `uninstall.yml`
- `restart_observability_platform.yml` → `start.yml` (after stop)
- `start_docker_desktop.yml` → `install.yml` (Windows tasks)

## Future Enhancements

- Support for additional Linux distributions
- Kubernetes deployment option
- Backup/restore functionality
- Monitoring and alerting setup