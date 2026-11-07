# Elastic Agent Configuration

This directory contains declarative configuration for Elastic Agent
deployments across the Spark-on-Kubernetes infrastructure. The
lifecycle automation that deploys this directory's content lives at
`automation/ansible/playbooks/elastic-agent/` (install/start/stop/
diagnose/uninstall).

## Platform support

Linux only. This repo once also deployed to a Windows host (`GaryPC`,
via `elastic-agent.GaryPC.yml` and the `envconf_to_win_env.py` helper);
both were removed when the lab dropped that host. The current
`install.yml` playbook has no Windows branch at all. If Windows support
is needed again, re-add it as a parallel template
(`elastic-agent.windows.yml.j2`) and OS-conditional tasks in
`install.yml` — the line is intentionally drawn here for now rather than
carried as unused code.

## Configuration Files

| File | Purpose | Status |
|------|---------|--------|
| **elastic-agent.linux.yml.j2** | Jinja2 template for Linux hosts | ✅ Active (deployed via Ansible) |
| **bin/gpu-metrics.py** | AMD GPU sysfs metrics collector, run via systemd timer | ✅ Active |

Agent environment variables (`ELASTIC_URL`, `ELASTIC_USER`,
`ELASTIC_PASSWORD`, `CA_CERT`, `LS_HOST`, `LS_SPARK_EVENTS_PORT`) are
not a static file here -- they're generated from `vars/variables.yaml`
into `vars/contexts/elastic_agent_env.conf` and deployed to
`/etc/elastic-agent/elastic_agent_env.conf` on each host.

## Deployment

Elastic Agent configurations are deployed using Ansible playbooks with a **template-based approach**:

1. **Template:** `elastic-agent.linux.yml.j2` (Jinja2 template)
2. **Variables:** `automation/ansible/host_vars/<hostname>.yml` (host-specific overrides)
3. **Playbook:** `automation/ansible/playbooks/elastic-agent/install.yml`
4. **Destination:** `/opt/Elastic/Agent/elastic-agent.yml` (on managed nodes)

### Quick Deployment

```bash
# Deploy to all Linux hosts
cd automation/ansible
ansible-playbook -i inventory.yml playbooks/elastic-agent/install.yml -l Lab1,Lab2

# Deploy to single host
ansible-playbook -i inventory.yml playbooks/elastic-agent/install.yml -l Lab2

# Check status
ansible-playbook -i inventory.yml playbooks/elastic-agent/diagnose.yml
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

- Script: `bin/gpu-metrics.py` (this directory)
- Deployed to: `/opt/Elastic/Agent/extensions/gpu-metrics.py`
- Runs via the Filebeat `exec` input every 10 seconds (low overhead)
- Reads utilization, clocks, temperature, power, and fan speed from `/sys/class/drm/card*/device/**`
- Produces JSON documents tagged with `event.kind: metric` so they land in the `metrics-gpu-default` data stream

## Host Variables

Host-specific behavior is controlled via `automation/ansible/host_vars/<hostname>.yml`:

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
vim specifications/elastic-agent/elastic-agent.linux.yml.j2

# Validate YAML syntax
yamllint specifications/elastic-agent/elastic-agent.linux.yml.j2

# Deploy to all hosts
cd automation/ansible
ansible-playbook -i inventory.yml playbooks/elastic-agent/install.yml -l Lab1,Lab2
```

### Change Host-Specific Behavior

```bash
# Edit host variables
vim automation/ansible/host_vars/Lab1.yml

# Redeploy to that host only
cd automation/ansible
ansible-playbook -i inventory.yml playbooks/elastic-agent/install.yml -l Lab1
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
- Host-specific variables in `automation/ansible/host_vars/`
- Playbook uses template rendering
- Scalable - new hosts only need `host_vars/<hostname>.yml`

**Migration Date:** November 12, 2025

## Files Removed

- `elastic-agent.Lab1.yml`, `elastic-agent.Lab2.yml`, `elastic-agent.lab1.yml` -- replaced by the template + `host_vars/` approach (2025-11-12).
- `elastic-agent.GaryPC.yml` -- the Windows per-host config, unused once the Windows (`GaryPC`) host left the lab.
- `envconf_to_win_env.py` -- Windows env-file conversion helper, dead code once `elastic-agent.GaryPC.yml` was removed; no playbook ever called it.
- `elastic-agent.local.yml` -- a manually-copied template for monitoring a developer's own local PySpark client workstation (`/tmp/spark/events/`), not part of any deployed/automated path. Removed for the same reason: no playbook referenced it.
- `*.bak` backup files.

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
yamllint specifications/elastic-agent/elastic-agent.linux.yml.j2

# Update certificate (pull-based: re-run start to test currency and re-fetch from observability volume)
ansible-playbook -i automation/ansible/inventory.yml automation/ansible/playbooks/elastic-agent/start.yml --limit native
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
curl -k -u elastic:myElastic2025 "https://Lab3.lan:9200/_cat/indices/metrics-system*"

# Check agent status
ansible Lab1,Lab2 -m shell -a "sudo /opt/Elastic/Agent/elastic-agent status"
```

## Related Files

- `automation/ansible/playbooks/elastic-agent/install.yml` - Installation playbook
- `automation/ansible/playbooks/elastic-agent/start.yml` - Start agent service
- `automation/ansible/playbooks/elastic-agent/stop.yml` - Stop agent service
- `automation/ansible/playbooks/elastic-agent/diagnose.yml` - Check agent status
- `automation/ansible/playbooks/elastic-agent/uninstall.yml` - Remove agent service
- `automation/ansible/host_vars/Lab1.yml` - Lab1-specific variables
- `automation/ansible/host_vars/Lab2.yml` - Lab2-specific variables
