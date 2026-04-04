# Observability Platform Playbooks

Ansible playbooks for managing the observability platform (Elasticsearch, Kibana, Grafana, Logstash, Prometheus, Tempo, OTel Collector, Elastic Agent).

## Directory layout

```
observability/
├── deploy.yml              # Orchestrator: deploy all subsystems
├── start.yml               # Orchestrator: start all services + health checks
├── stop.yml                # Orchestrator: docker compose down
├── test.yml                # Orchestrator: data-flow assertions
├── diagnose.yml            # Orchestrator: full platform diagnostics
├── uninstall.yml           # Orchestrator: remove everything
├── install.yml             # Alias for deploy.yml
├── status.yml              # DEPRECATED → diagnose.yml
├── elasticsearch/
│   ├── deploy.yml          # Sync ES config files
│   ├── start.yml           # Start ES + wait healthy
│   ├── stop.yml            # Stop ES container
│   ├── test.yml            # Cluster health + index freshness
│   └── diagnose.yml        # Connectivity, container, index report
├── kibana/
│   ├── start.yml           # Start Kibana + wait healthy
│   ├── stop.yml            # Stop Kibana container
│   └── diagnose.yml        # HTTP, container, API level
├── grafana/
│   ├── deploy.yml          # Sync Grafana config + plugins dir
│   ├── start.yml           # Start Grafana + wait healthy
│   ├── stop.yml            # Stop Grafana container
│   └── diagnose.yml        # HTTP, dashboard listing
├── logstash/
│   ├── deploy.yml          # Sync Logstash config
│   ├── start.yml           # Start Logstash + wait API
│   ├── stop.yml            # Stop Logstash container
│   ├── test.yml            # Network IO + disk IO freshness
│   └── diagnose.yml        # Container, API, pipelines, OOM check
├── otel-collector/
│   ├── deploy.yml          # Sync OTel Collector config
│   ├── start.yml           # Start OTel Collector
│   ├── stop.yml            # Stop OTel Collector
│   └── diagnose.yml        # Container + health endpoint
├── tempo/
│   ├── deploy.yml          # Sync Tempo config
│   ├── start.yml           # Start Tempo + wait ready
│   ├── stop.yml            # Stop Tempo container
│   └── diagnose.yml        # Container + readiness
├── prometheus/
│   ├── deploy.yml          # Sync config + K8s exporters
│   ├── start.yml           # Verify exporters + Prometheus
│   ├── stop.yml            # Stop Prometheus + OTel Collector
│   ├── diagnose.yml        # Targets, metrics, exporter pods
│   ├── uninstall.yml       # Remove K8s exporters
│   └── README.md
└── elastic-agent/
    ├── test.yml            # System CPU/memory freshness
    └── diagnose.yml        # Agent service status on all hosts
```

## Usage

### Full stack operations

```bash
cd ansible

# Deploy all config files + build Docker images
ansible-playbook -i inventory.yml playbooks/observability/deploy.yml

# Start all services
ansible-playbook -i inventory.yml playbooks/observability/start.yml

# Stop all services (preserve data)
ansible-playbook -i inventory.yml playbooks/observability/stop.yml

# Stop and delete volumes (fresh start)
ansible-playbook -i inventory.yml playbooks/observability/stop.yml -e delete_volumes=true

# Full diagnostic
ansible-playbook -i inventory.yml playbooks/observability/diagnose.yml

# Behavior tests (data flow assertions)
ansible-playbook -i inventory.yml playbooks/observability/test.yml

# Complete removal
ansible-playbook -i inventory.yml playbooks/observability/uninstall.yml
```

### Single-subsystem operations

Each subsystem can be managed independently:

```bash
# Restart only Logstash
ansible-playbook -i inventory.yml playbooks/observability/logstash/stop.yml
ansible-playbook -i inventory.yml playbooks/observability/logstash/start.yml

# Diagnose only Elasticsearch
ansible-playbook -i inventory.yml playbooks/observability/elasticsearch/diagnose.yml

# Redeploy only Grafana dashboards
ansible-playbook -i inventory.yml playbooks/observability/grafana/deploy.yml

# Check Elastic Agent status on all hosts
ansible-playbook -i inventory.yml playbooks/observability/elastic-agent/diagnose.yml
```

## Host requirements

All observability services run on the **observability** host group (Lab3). Run from `spark-observability/ansible` with a control node that can SSH as `ansible_user` (see `inventory.yml`).

## Service URLs

| Service       | URL                           |
|---------------|-------------------------------|
| Elasticsearch | https://Lab3.lan:9200         |
| Kibana        | http://Lab3.lan:5601          |
| Grafana       | http://Lab3.lan:3000          |
| Logstash      | Lab3.lan:5050 / :5051         |
| Prometheus    | http://Lab3.lan:9090          |
| Tempo         | http://Lab3.lan:3200          |

## License and trial reset (Watcher)

Watcher requires a **trial** or paid license. For lab use, run the trial license (30 days). When expired, reset the cluster for a new trial:

```bash
ansible-playbook -i inventory.yml playbooks/observability/stop.yml -e delete_volumes=true
ansible-playbook -i inventory.yml playbooks/observability/start.yml
```
