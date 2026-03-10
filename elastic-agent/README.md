# Elastic Agent Configuration

This directory contains configuration files for Elastic Agent deployments across the Spark-on-Kubernetes infrastructure.

## Configuration Files

| File | Purpose | Status |
|------|---------|--------|
| **elastic-agent.linux.yml.j2** | Jinja2 template for Linux hosts | ✅ Active (deployed via Ansible) |
| **elastic-agent.linux.yml** | Static Linux configuration | 📋 Reference only |
| **elastic-agent.windows.yml** | Windows configuration | 🔮 Future use |
| **elastic-agent.local.yml** | Local client testing | 🧪 Development only |
| **elastic_agent_env_systemd.conf** | Environment variables for systemd | ✅ Active |

## Deployment

Elastic Agent configurations are deployed using Ansible playbooks with a **template-based approach**:

1. **Template:** `elastic-agent.linux.yml.j2` (Jinja2 template)
2. **Variables:** `ansible/host_vars/<hostname>.yml` (host-specific overrides)
3. **Playbook:** `ansible/playbooks/elastic-agent/install.yml`
4. **Destination:** `/opt/Elastic/Agent/elastic-agent.yml` (on managed nodes)

### Quick Deployment

```bash
# Deploy to all Linux hosts
cd ansible
ansible-playbook playbooks/elastic-agent/install.yml -l Lab1,Lab2

# Deploy to single host
ansible-playbook playbooks/elastic-agent/install.yml -l Lab2

# Check status
ansible-playbook playbooks/elastic-agent/status.yml
```

## Architecture

The Elastic Agent collects **five types of telemetry**:

1. **System Metrics** - CPU, memory, network, disk (per-host)
2. **Kubernetes Metrics** - K8s cluster metrics (currently disabled)
3. **Spark Logs** - Application logs and GC metrics (per-pod)
4. **Spark Events** - Job execution events (Lab2 only - NFS server)
5. **GPU Metrics** - AMD Radeon RX 7600M XT utilization/temperature/power via sysfs

### Key Design Decisions

**OS-Based Configuration:**
- Single `linux.yml.j2` template for all Linux hosts
- Host-specific behavior via Ansible `host_vars/`
- No per-host configuration files (scalable approach)

**Duplicate Prevention:**
- Event logs (`/mnt/spark/events`) are NFS-shared
- Only Lab2 (NFS server) collects events
- Lab1 has `spark_events_enabled: false` in host_vars

**Proper Routing:**
- System metrics → Elasticsearch (direct)
- Spark logs → Elasticsearch (direct)
- Spark events → Logstash → Elasticsearch (JSON processing)
- GPU metrics → Elastic Agent exec input → Elasticsearch data stream `metrics-gpu-default`

### GPU Metrics Collector

- Script: `elastic-agent/bin/gpu-metrics.py`
- Deployed to: `/opt/Elastic/Agent/extensions/gpu-metrics.py`
- Runs via the Filebeat `exec` input every 10 seconds (low overhead)
- Reads utilization, clocks, temperature, power, and fan speed from `/sys/class/drm/card*/device/**`
- Produces JSON documents tagged with `event.kind: metric` so they land in the `metrics-gpu-default` data stream

## Host Variables

Host-specific behavior is controlled via `ansible/host_vars/<hostname>.yml`:

**Lab1 Variables:**
```yaml
spark_events_enabled: false  # Prevents duplicate event collection (NFS client)
spark_app_logs_enabled: true
spark_gc_logs_enabled: true
```

**Lab2 Variables:**
```yaml
spark_events_enabled: true   # Collects events (NFS server)
spark_app_logs_enabled: true
spark_gc_logs_enabled: true
```

## Documentation

For detailed architecture, troubleshooting, and best practices:

📚 **[Elastic Agent Architecture](docs/Elastic_Agent_Architecture.md)** - Comprehensive guide covering:
- Telemetry types and collection strategies
- Architecture principles and data flows
- Configuration management
- Preventing duplicate collection
- Deployment procedures
- Monitoring and troubleshooting
- Future enhancements

## Common Tasks

### Update Configuration Template

```bash
# Edit the Jinja2 template
vim elastic-agent/elastic-agent.linux.yml.j2

# Validate YAML syntax
yamllint elastic-agent/elastic-agent.linux.yml.j2

# Deploy to all hosts
cd ansible
ansible-playbook playbooks/elastic-agent/install.yml -l Lab1,Lab2
```

### Change Host-Specific Behavior

```bash
# Edit host variables
vim ansible/host_vars/Lab1.yml

# Redeploy to that host only
cd ansible
ansible-playbook playbooks/elastic-agent/install.yml -l Lab1
```

### Verify Deployment

```bash
# Check deployed configuration
ansible Lab1 -m shell -a "head -20 /opt/Elastic/Agent/elastic-agent.yml"

# Verify event collection is disabled on Lab1
ansible Lab1 -m shell -a "grep -A 3 'id: spark-events' /opt/Elastic/Agent/elastic-agent.yml | grep enabled"

# Expected: enabled: false

# Verify event collection is enabled on Lab2
ansible Lab2 -m shell -a "grep -A 3 'id: spark-events' /opt/Elastic/Agent/elastic-agent.yml | grep enabled"

# Expected: enabled: true
```

### Check Agent Health

```bash
# Check status
ansible Lab1,Lab2 -m shell -a "sudo /opt/Elastic/Agent/elastic-agent status"

# Check for certificate errors
ansible Lab2 -m shell -a "sudo tail -100 /var/log/elastic-agent/elastic-agent-*.ndjson | grep -i x509 | wc -l"

# Expected: 0 (no certificate errors)
```

## Migration History

**Previous Approach (Deprecated):**
- Per-host configuration files: `elastic-agent.Lab1.yml`, `elastic-agent.Lab2.yml`
- Playbook used `{{ inventory_hostname }}` for file selection
- Not scalable - each new host required a new config file

**Current Approach (Active):**
- Single OS-based template: `elastic-agent.linux.yml.j2`
- Host-specific variables in `ansible/host_vars/`
- Playbook uses template rendering
- Scalable - new hosts only need `host_vars/<hostname>.yml`

**Migration Date:** November 12, 2025

## Files Removed

As part of the consolidation to template-based configuration, the following per-host files were removed:
- `elastic-agent.Lab1.yml` (replaced by template)
- `elastic-agent.Lab2.yml` (replaced by template)
- `elastic-agent.lab1.yml` (old lowercase version)
- `elastic-agent.GaryPC.yml` (unused)
- `*.bak` backup files

## Environment Variables

Agent configuration uses environment variables from systemd:

**File:** `elastic_agent_env_systemd.conf`  
**Deployed to:** `/etc/elastic-agent/elastic_agent_env.conf`  
**Loaded by:** Elastic Agent systemd service

**Key Variables:**
- `ELASTIC_URL` - Elasticsearch endpoint
- `ELASTIC_USER` - Elasticsearch username
- `ELASTIC_PASSWORD` - Elasticsearch password
- `CA_CERT` - CA certificate path (standard path for all services)
- `LS_HOST` - Logstash hostname
- `LS_SPARK_EVENTS_PORT` - Logstash port for Spark events

## Troubleshooting

### Agent Shows DEGRADED

**Common Causes:**
1. Certificate mismatch (x509 errors)
2. YAML indentation errors
3. Unsupported input types (e.g., `system/logs`)
4. Elasticsearch unavailable

**Solution:**
```bash
# Check agent logs
ansible Lab2 -m shell -a "sudo tail -200 /var/log/elastic-agent/elastic-agent-*.ndjson"

# Validate YAML
yamllint elastic-agent/elastic-agent.linux.yml.j2

# Update certificate (pull-based: re-run start to test currency and re-fetch from observability volume)
ansible-playbook -i ansible/inventory.yml ansible/playbooks/elastic-agent/start.yml --limit native
```

### Duplicate Event Collection

**Symptom:** Same event appears multiple times in Elasticsearch

**Diagnosis:**
```bash
# Check which hosts are collecting events
ansible Lab1,Lab2 -m shell -a "grep 'spark-events' /opt/Elastic/Agent/elastic-agent.yml | grep enabled"

# Expected:
# Lab1: enabled: false
# Lab2: enabled: true
```

**Solution:** Verify `host_vars/` and redeploy

### No Data Flowing

**Check:**
```bash
# Verify data in Elasticsearch
curl -k -u elastic:myElastic2025 "https://GaryPC.local:9200/_cat/indices/metrics-system*"

# Check agent status
ansible Lab1,Lab2 -m shell -a "sudo /opt/Elastic/Agent/elastic-agent status"
```

## Related Files

- `ansible/playbooks/elastic-agent/install.yml` - Installation playbook
- `ansible/playbooks/elastic-agent/start.yml` - Start agent service
- `ansible/playbooks/elastic-agent/stop.yml` - Stop agent service
- `ansible/playbooks/elastic-agent/status.yml` - Check agent status
- `ansible/host_vars/Lab1.yml` - Lab1-specific variables
- `ansible/host_vars/Lab2.yml` - Lab2-specific variables

