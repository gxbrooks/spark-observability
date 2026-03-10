# Observability Platform Playbooks

This directory contains the consolidated playbooks for managing the observability platform (Elasticsearch, Kibana, Grafana, Logstash, Prometheus, Tempo).

## Playbook Structure

### Core Playbooks (Top Level)

Each top-level playbook automatically imports the corresponding sub-system playbook
at the end of its run via `import_playbook`.

| Playbook | Purpose | Imports |
|---|---|---|
| `deploy.yml` | Copy config files to observability host; build Docker images | `prometheus/deploy.yml` |
| `start.yml` | Start all observability containers; validate health | `prometheus/start.yml` |
| `stop.yml` | Stop all observability containers | *(note only — K8s exporters keep running)* |
| `diagnose.yml` | Full platform health check + recent data availability | `prometheus/diagnose.yml` |
| `uninstall.yml` | Remove all containers, volumes, and files | `prometheus/uninstall.yml` |
| `status.yml` | Quick service status overview | — |

### Prometheus Sub-Playbooks (`prometheus/`)

Manage the Prometheus metrics pipeline and Kubernetes monitoring exporters independently.
See [`prometheus/README.md`](prometheus/README.md) for full details.

| Sub-Playbook | Purpose |
|---|---|
| `prometheus/deploy.yml` | Sync Prometheus config + deploy node-exporter and kube-state-metrics to K8s |
| `prometheus/start.yml` | Ensure Prometheus and OTel Collector are running; verify K8s exporter pods |
| `prometheus/stop.yml` | Stop Prometheus and OTel Collector only (targeted, leaves rest of stack running) |
| `prometheus/diagnose.yml` | Prometheus target status, key metric availability, K8s exporter pod health |
| `prometheus/uninstall.yml` | Remove K8s exporters from cluster |

### Usage Examples

```bash
# Complete deployment (first time) - also deploys node-exporter + kube-state-metrics to K8s
ansible-playbook -i ansible/inventory.yml ansible/playbooks/observability/deploy.yml

# Start services (after deployment) - also verifies K8s exporter pods
ansible-playbook -i ansible/inventory.yml ansible/playbooks/observability/start.yml

# Stop services
ansible-playbook -i ansible/inventory.yml ansible/playbooks/observability/stop.yml

# Full diagnostic (platform + Prometheus pipeline + K8s exporters)
ansible-playbook -i ansible/inventory.yml ansible/playbooks/observability/diagnose.yml

# Complete removal - also removes K8s exporters from cluster
ansible-playbook -i ansible/inventory.yml ansible/playbooks/observability/uninstall.yml

# Prometheus only - deploy/redeploy K8s exporters
ansible-playbook -i ansible/inventory.yml ansible/playbooks/observability/prometheus/deploy.yml

# Prometheus only - diagnose metrics pipeline
ansible-playbook -i ansible/inventory.yml ansible/playbooks/observability/prometheus/diagnose.yml
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

- **Elasticsearch**: https://GaryPC.lan:9200
- **Kibana**: http://GaryPC.lan:5601
- **Grafana**: http://GaryPC.lan:3000
- **Logstash**: GaryPC.lan:5050
- **Prometheus**: http://GaryPC.lan:9090
- **Tempo**: http://GaryPC.lan:3200

## Credentials

- **Elasticsearch/Kibana**: elastic / myElastic2025
- **Grafana**: Check `.env` file for admin password

## License and trial reset (Watcher)

Watcher requires a **trial** or paid (Gold/Platinum/Enterprise) license; the free **basic** license does not include Watcher. For private lab use the practical option is the **trial** license.

- **Trial**: 30 days, includes Watcher and security. Can be started only **once per cluster** (Elastic restriction); after expiry it cannot be restarted on the same cluster.
- **Basic**: Free and perpetual, but no Watcher.

**Lab workflow with Watcher:**

1. Keep `LICENSE=trial` in your observability env (e.g. `vars/variables.yaml` and generated `.env`). The install/start flow runs `init-index.sh`, which starts a trial on a fresh cluster when it sees a basic license.
2. When the trial expires (after ~30 days), Kibana will show license/security compliance errors and Watcher will stop. To get a new trial you must **reset the cluster** (new cluster = new trial eligibility).
3. **Reset for new trial** (all Elasticsearch and Kibana data is removed; acceptable if you do not need to retain more than 30 days):

   ```bash
   # From your control node (e.g. Lab2), with inventory path as usual:
   ansible-playbook -i ansible/inventory.yml ansible/playbooks/observability/stop.yml -e delete_volumes=true
   ansible-playbook -i ansible/inventory.yml ansible/playbooks/observability/start.yml
   ```

   `stop.yml -e delete_volumes=true` removes all Docker volumes (including `esdata`). The next `start.yml` brings up a fresh Elasticsearch; `init-index` runs and starts a new 30-day trial.

4. If you need longer retention without resetting, you would need a paid Gold/Platinum/Enterprise license installed via the Elasticsearch license API.

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