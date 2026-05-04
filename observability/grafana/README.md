# Grafana Dashboards for Spark Observability

This directory contains Grafana dashboards for monitoring Spark on Kubernetes with comprehensive system and application metrics.

## Overview

Grafana provides visualization of metrics collected from:
- **Host-level system metrics** (CPU, memory, network, disk)
- **Docker container metrics** (when running on Docker)
- **Kubernetes container metrics** (future)
- **Spark application metrics** (GC, heap, jobs)

## Accessing Grafana

**URL**: `http://garypc.local:3000/`  
**Default Credentials**: Check your deployment configuration

## Available Dashboards

| Dashboard | UID | Description | Documentation |
|-----------|-----|-------------|---------------|
| Spark Cluster Metrics | `spark-system-metrics` | Host and Spark metrics | [spark-system-metrics.md](./dashboards/spark-system-metrics.md) |
| Hosts | `lab-hosts-metrics` | Lab1–Lab3 system, network, disk, and GPU metrics (subset of Spark system panels) | — |

## Dashboard Organization

```
grafana/
├── README.md (this file)
├── grafana.ini                    # Grafana configuration
├── provisioning/
│   ├── datasources/
│   │   └── datasources.yaml       # Elasticsearch datasource config
│   └── dashboards/
│       ├── provisioning.yaml      # Dashboard provisioning config
│       ├── spark-system.json      # Spark cluster metrics dashboard
│       └── hosts.json             # Lab1–Lab3 host metrics only
└── dashboards/                    # Documentation for select dashboards
    └── spark-system-metrics.md
```

## Data Sources

### Elasticsearch
- **Type**: Elasticsearch
- **URL**: `https://es01:9200/` (internal Docker network)
- **Authentication**: Basic auth with elastic user
- **TLS**: Currently using `tlsSkipVerify: true`
- **UID**: `spark-elasticsearch` (used in dashboard queries)

## Metrics Collection

### Host-Level Metrics
Collected by **Elastic Agent** running as systemd service on each host:
- **Source**: Lab1, Lab2, GaryPC-WSL
- **Indices**: `metrics-system.*`
- **Fields**: CPU, memory, network, disk I/O, filesystem, load average
- **Frequency**: Every 10-30 seconds

### Spark Application Metrics
Collected from Spark event logs and GC logs:
- **Source**: Spark containers in Kubernetes
- **Indices**: `logs-spark_gc-default`, `logs-spark-spark`
- **Fields**: GC pause times, heap usage, reclaimed memory
- **Processing**: Elastic Agent → Logstash → Elasticsearch

### Batch job data (Elasticsearch / Kibana)
Batch lifecycle and traces are indexed for search and watchers (not surfaced in a Grafana dashboard here). See [`../elasticsearch/docs/Elasticsearch_indices.md`](../elasticsearch/docs/Elasticsearch_indices.md) and Kibana saved objects under [`../elasticsearch/config/batch-events/`](../elasticsearch/config/batch-events/) and related config.

## Creating New Dashboards

### Method 1: Grafana UI (Development)
1. Open Grafana web interface
2. Create → Dashboard
3. Add panels and configure queries
4. Save dashboard
5. Export JSON via Settings → JSON Model
6. Save to `provisioning/dashboards/<name>.json`

### Method 2: Direct JSON (Production)
1. Create dashboard JSON file in `provisioning/dashboards/`
2. Set appropriate `uid` and `title`
3. Configure datasource references
4. Restart Grafana or wait for auto-reload

### Dashboard Best Practices
- **UIDs**: Use descriptive, unique IDs (e.g., `spark-system-metrics`)
- **Time Field**: Always use `@timestamp`
- **Refresh**: Set appropriate auto-refresh interval (10s-60s)
- **Variables**: Use template variables for dynamic filtering
- **Legends**: Include hostname/container name in aliases
- **Calculations**: Show rates (derivative) not absolute counters for throughput

## Deployment

Dashboards are automatically provisioned when Grafana starts:

```yaml
# provisioning/dashboards/provisioning.yaml
- name: 'default'
  folder: ''
  type: file
  options:
    path: /etc/grafana/provisioning/dashboards
```

### Manual Deployment
```bash
# Copy dashboard to GaryPC
ansible -i ansible/inventory.yml GaryPC-WSL -m copy \
  -a "src=observability/grafana/provisioning/dashboards/<dashboard>.json \
      dest=/home/ansible/observability/grafana/provisioning/dashboards/<dashboard>.json"

# Restart Grafana
ansible -i ansible/inventory.yml GaryPC-WSL -m shell \
  -a "cd /home/ansible/observability && docker-compose restart grafana"
```

## Troubleshooting

### Dashboard Not Appearing
1. Check Grafana logs: `docker logs grafana`
2. Verify file exists in provisioning directory
3. Restart Grafana container
4. Check for JSON syntax errors

### Panels Show "No Data"
1. **Check time range**: Extend to 24 hours or 7 days
2. **Verify indices exist**: Query Elasticsearch directly
3. **Check datasource**: Ensure Elasticsearch connection is healthy
4. **Inspect query**: Use Grafana's query inspector

### Slow Dashboard Loading
1. Reduce time range
2. Increase query interval
3. Limit number of series returned
4. Use metric aggregations (avg, max) instead of raw values

## Further Reading

- [Grafana Elasticsearch Datasource](https://grafana.com/docs/grafana/latest/datasources/elasticsearch/)
- [Dashboard Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/#dashboards)
- [Time Series Panel](https://grafana.com/docs/grafana/latest/panels/visualizations/time-series/)

