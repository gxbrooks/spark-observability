# Observability Platform Playbooks

This directory contains Ansible playbooks for managing the Docker-based observability platform on GaryPC WSL.

## Overview

The observability platform consists of:
- **Elasticsearch**: Data storage and search engine
- **Kibana**: Data visualization and dashboarding
- **Grafana**: Advanced monitoring and alerting
- **Logstash**: Data processing and transformation

## Prerequisites

- Docker Desktop installed and running on GaryPC WSL
- Docker Compose available
- SSH access to GaryPC WSL on port 2222
- User `ansible` with appropriate permissions

## Playbooks

### 1. `setup_observability_repo.yml`
Sets up the observability directory structure and copies files from the development repository.

**Usage:**
```bash
ansible-playbook -i ../inventory.yml setup_observability_repo.yml
```

### 2. `install_observability.yml`
Checks prerequisites and prepares the system for observability platform deployment.

**Usage:**
```bash
ansible-playbook -i ../inventory.yml install_observability.yml
```

### 3. `deploy_observability.yml`
Deploys the complete observability platform with all services.

**Usage:**
```bash
ansible-playbook -i ../inventory.yml deploy_observability.yml
```

### 4. `start_observability.yml`
Starts the observability platform services.

**Usage:**
```bash
ansible-playbook -i ../inventory.yml start_observability.yml
```

### 5. `stop_observability.yml`
Stops the observability platform services (containers remain).

**Usage:**
```bash
ansible-playbook -i ../inventory.yml stop_observability.yml
```

### 6. `shutdown_observability.yml`
Completely shuts down the observability platform and removes containers/networks.

**Usage:**
```bash
ansible-playbook -i ../inventory.yml shutdown_observability.yml
```

### 7. `status_observability.yml`
Checks the status of all observability platform services.

**Usage:**
```bash
ansible-playbook -i ../inventory.yml status_observability.yml
```

### 8. `uninstall_observability.yml`
Completely removes the observability platform and cleans up all resources.

**Usage:**
```bash
ansible-playbook -i ../inventory.yml uninstall_observability.yml
```

## Service URLs

Once deployed, the following services will be available:

- **Elasticsearch**: `https://GaryPC.lan:9200`
- **Kibana**: `http://GaryPC.lan:5601`
- **Grafana**: `http://GaryPC.lan:3000`
- **Logstash**: `GaryPC.lan:9600`

## Architecture

The observability platform uses Docker Compose with the following architecture:

```
init-certs → es01 → init-kibana-password → kibana
    ↓                    ↓
init-index → logstash01 → [Data Processing]
    ↓
grafana → [Monitoring & Alerting]
```

## Data Flow

1. **Elastic Agents** on each host collect telemetry data
2. **Logstash** processes and transforms the data
3. **Elasticsearch** stores the processed data
4. **Kibana** provides data visualization and dashboards
5. **Grafana** provides advanced monitoring and alerting

## Troubleshooting

### Common Issues

1. **Docker not running**: Ensure Docker Desktop is started on GaryPC WSL
2. **Port conflicts**: Check if ports 9200, 5601, 3000, or 9600 are already in use
3. **Network issues**: Ensure the `elastic` Docker network is created
4. **Permission issues**: Ensure the user has appropriate Docker permissions

### Logs

Check container logs:
```bash
docker-compose -f /home/gxbrooks/repos/elastic-on-spark/observability/docker-compose.yml logs [service_name]
```

### Health Checks

- **Elasticsearch**: `curl -k https://GaryPC.lan:9200`
- **Kibana**: `curl http://GaryPC.lan:5601`
- **Grafana**: `curl http://GaryPC.lan:3000`
- **Logstash**: `curl http://GaryPC.lan:9600`

## Environment Variables

The platform uses environment variables defined in `.env` file, which is generated from `variables.yaml` by `generate_env.py`.

Key variables:
- `ELASTIC_PASSWORD`: Elasticsearch password
- `KIBANA_PASSWORD`: Kibana password
- `STACK_VERSION`: Elastic Stack version
- `TZ`: Timezone setting
