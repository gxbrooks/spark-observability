# Elastic Agent Telemetry Collection Architecture

**Version:** 1.0  
**Last Updated:** November 12, 2025  
**Agent Version:** 8.15.0  
**Deployment Mode:** Standalone (not Fleet-managed)

---

## Table of Contents

- [Overview](#overview)
- [Telemetry Types](#telemetry-types)
- [Architecture Principles](#architecture-principles)
- [Collection Flows](#collection-flows)
- [Configuration Management](#configuration-management)
- [Data Destinations](#data-destinations)
- [Preventing Duplicate Collection](#preventing-duplicate-collection)
- [Deployment](#deployment)
- [Monitoring & Troubleshooting](#monitoring--troubleshooting)

---

## Overview

The Elastic Agent collects four distinct types of telemetry from the Spark-on-Kubernetes infrastructure:

1. **System Metrics** - Host-level performance metrics (CPU, memory, network, disk)
2. **Kubernetes Metrics** - K8s cluster and pod metrics (currently disabled)
3. **Spark Log Collection** - Application logs and GC metrics from Spark pods
4. **Spark Event Collection** - Cluster-wide job execution events

Each telemetry type follows Elastic best practices while addressing the unique challenges of distributed Spark deployments.

---

## Telemetry Types

### 1. System Metrics Collection

**Purpose:** Monitor host-level resource utilization  
**Scope:** Per-host collection (Lab1, Lab2)  
**Source:** Elastic Agent `system/metrics` input  
**Destination:** Elasticsearch (direct)  
**Data Streams:**
- `metrics-system.cpu-default`
- `metrics-system.memory-default`
- `metrics-system.network-default`
- `metrics-system.diskio-default`
- `metrics-system.filesystem-default`
- `metrics-system.load-default`

**Collection Strategy:**
- Each Elastic Agent collects metrics for its own host
- No risk of duplication (automatically host-specific via `host.name` field)
- Follows Elastic best practices for system monitoring

**Metricsets:**
```yaml
- cpu       # CPU utilization and stats
- memory    # Memory usage and swap
- network   # Network I/O by interface
- diskio    # Disk I/O statistics
- filesystem # Filesystem usage
- load      # System load average
```

**Key Fields:**
- `host.name` - Automatically identifies the source host
- `@timestamp` - Metric collection timestamp
- `system.cpu.total.pct` - Overall CPU utilization percentage
- `system.memory.used.pct` - Memory utilization percentage

---

### 2. Kubernetes Metrics Collection

**Purpose:** Monitor K8s cluster and pod metrics  
**Scope:** Per-host collection (for pods running on that node)  
**Source:** Elastic Agent `kubernetes/metrics` input  
**Destination:** Elasticsearch (direct)  
**Status:** **DISABLED** (Currently commented out)

**Planned Configuration:**
```yaml
- type: kubernetes/metrics
  enabled: false  # Disabled pending proper configuration
  add_metadata: true
  kube_config: "${KUBECONFIG}"
  ```

**Rationale for Disabling:**
- Requires proper RBAC and kubeconfig setup
- Potential overlap with existing K8s monitoring solutions
- Will be enabled in future phase

---

### 3. Spark Log Collection

**Purpose:** Collect application logs and GC metrics from Spark pods  
**Scope:** Per-host collection (pod-specific logs)  
**Source:** Filestream inputs monitoring `/mnt/spark/logs`  
**Destination:** Elasticsearch (direct)

#### 3a. Spark Application Logs

**Path Pattern:** `/mnt/spark/logs/*/spark-app.log*`  
**Data Stream:** `logs-spark-default`  
**Multiline:** Yes (stack trace support)

**Log Format:**
```
2025-11-12 08:15:30 INFO  Master:190 - Registering app MyApp
2025-11-12 08:15:31 ERROR TaskScheduler:123 - Task failed
  at org.apache.spark.scheduler.TaskScheduler.taskFailed(TaskScheduler.scala:456)
  at org.apache.spark.scheduler.DAGScheduler.handleTaskFailed(DAGScheduler.scala:789)
```

**Key Features:**
- Multiline parsing for Java stack traces
- Lines NOT starting with timestamp are appended to previous entry
- Stack traces stored in separate field: `error.stack_trace`
- Clean message in: `log_message`

**Configuration:**
```yaml
- id: spark-app-logs
  type: filestream
  paths:
    - '/mnt/spark/logs/*/spark-app.log*'
  parsers:
    - multiline:
        type: pattern
        pattern: '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}'
        negate: true
        match: after
```

**Pod-to-Host Mapping:**
- Each Kubernetes pod writes logs to `/opt/spark/logs/spark-app.log`
- K8s volume mounts map to host at: `/var/lib/kubelet/pods/<pod-id>/volume-subpaths/spark-logs-host/<container>/2`
- Symlinked to: `/mnt/spark/logs/<pod-name>/spark-app.log`
- Each host collects logs only from pods running on that node

**Preventing Duplication:**
- Lab1 collects: Lab1 worker pods
- Lab2 collects: Lab2 worker pods, master pod, history server pod
- No overlap because pod logs are local to each host

#### 3b. Spark GC Logs

**Path Pattern:** `/mnt/spark/logs/*/gc-*.log`  
**Data Stream:** `logs-spark_gc-default`  
**Multiline:** No

**Log Files:**
- `gc-driver.log` - Driver GC events
- `gc-executor.log` - Executor GC events  
- `gc-history.log` - History Server GC events
- `gc-master.log` - Master GC events

**Purpose:**
- Monitor JVM garbage collection performance
- Identify memory pressure and tuning needs
- Correlate GC pauses with application performance

**Configuration:**
```yaml
- id: spark-gc
  type: filestream
  paths:
    - '/mnt/spark/logs/*/gc-*.log'
  tags: ["spark-gc"]
```

---

### 4. Spark Event Collection

**Purpose:** Collect cluster-wide Spark job execution events  
**Scope:** **Single collection point** (Lab2 only)  
**Source:** Filestream input monitoring NFS-shared `/mnt/spark/events`  
**Destination:** Logstash (for JSON processing) → Elasticsearch

**Critical Architecture Decision:**
- `/mnt/spark/events` is an **NFS share** hosted by Lab2
- Lab1 mounts this share, creating potential for duplicate collection
- **Solution:** Only Lab2 (NFS server) collects events

**Event Files:**
- Path: `/mnt/spark/events/app-*`
- Format: Newline-delimited JSON (NDJSON)
- Created by: Spark drivers
- Consumed by: Spark History Server + Elastic Agent (Lab2)

**Event Types:**
- SparkListenerApplicationStart
- SparkListenerJobStart
- SparkListenerStageCompleted
- SparkListenerTaskEnd
- SparkListenerApplicationEnd
- And 30+ other event types

**Why Logstash?**
- Complex JSON transformation required
- Field extraction and enrichment
- Event type routing and filtering
- Timestamp normalization

**Configuration (Lab2 only):**
```yaml
- id: spark-events
  type: filestream
  use_output: "spark_events"  # Routes to Logstash
  enabled: {{ spark_events_enabled | default('true') }}
  streams:
    - paths:
        - "/mnt/spark/events/app-*"
      exclude_files: ['\.tmp$', '\.lock$']
      # NO JSON parsing here - let Logstash handle it
```

**Host Variables:**
```yaml
# Lab1 (ansible/host_vars/Lab1.yml)
spark_events_enabled: false  # Prevents duplicate collection

# Lab2 (ansible/host_vars/Lab2.yml)
spark_events_enabled: true   # NFS server collects
```

---

## Architecture Principles

### 1. Single Responsibility

Each agent collects only what it's responsible for:
- System metrics: Own host only
- Pod logs: Own pods only
- Event logs: NFS server only (Lab2)

### 2. No Duplication

**Problem:** NFS-shared directories can cause duplicate collection  
**Solution:** Use Ansible host variables to enable/disable inputs selectively

**Implementation:**
- `spark_events_enabled: false` on Lab1 (NFS client)
- `spark_events_enabled: true` on Lab2 (NFS server)

### 3. Proper Routing

Different data types have different processing needs:
- **Direct to Elasticsearch:** System metrics, pod logs (simple data)
- **Via Logstash:** Event logs (complex JSON transformation)

### 4. Scalability

**Current:** 2 hosts (Lab1, Lab2)  
**Future:** N hosts

**Design Decisions:**
- Use OS-based configs (`linux.yml.j2`) not per-host files
- Host-specific behavior via Ansible `host_vars/`
- Template-based deployment for flexibility

---

## Collection Flows

### Flow 1: System Metrics (Direct)

```
┌─────────────┐
│   Lab1/Lab2 │
│   Host OS   │
└──────┬──────┘
       │ system/metrics input
       ▼
┌─────────────┐
│ Elastic     │
│ Agent       │
└──────┬──────┘
       │ output: default (Elasticsearch)
       ▼
┌─────────────┐
│ Elasticsearch│
└──────┬──────┘
       │ Data Streams
       ▼
 metrics-system.cpu-default
 metrics-system.memory-default
 ...
```

### Flow 2: Spark Pod Logs (Direct)

```
┌─────────────────────────────┐
│ Spark Pod (Master/Worker)   │
│   /opt/spark/logs/          │
└──────────┬──────────────────┘
           │ K8s Volume Mount
           ▼
┌──────────────────────────────┐
│ Host: /var/lib/kubelet/pods/ │
│ Symlink: /mnt/spark/logs/    │
└──────────┬───────────────────┘
           │ filestream input
           ▼
┌──────────────────┐
│ Elastic Agent    │
│ (on same host)   │
└──────────┬───────┘
           │ output: default
           ▼
┌──────────────────┐
│ Elasticsearch    │
└──────────┬───────┘
           │ Data Streams
           ▼
    logs-spark-default
    logs-spark_gc-default
```

### Flow 3: Spark Events (via Logstash)

```
┌─────────────────────────┐
│ Spark Driver (any pod)  │
│ EventLoggingListener    │
└──────────┬──────────────┘
           │ Write NDJSON
           ▼
┌─────────────────────────┐
│ NFS: /srv/nfs/spark/    │
│      events/app-*       │
│ (Hosted on Lab2)        │
└──────────┬──────────────┘
           │ NFS mounted on Lab1 & Lab2
           │ (/mnt/spark/events)
           ▼
┌─────────────────────────┐
│ Elastic Agent (Lab2)    │
│ spark-events input      │
│ (Lab1 disabled)         │
└──────────┬──────────────┘
           │ output: spark_events (Logstash)
           ▼
┌─────────────────────────┐
│ Logstash:5050           │
│ - Parse JSON            │
│ - Extract fields        │
│ - Enrich metadata       │
└──────────┬──────────────┘
           │ elasticsearch output
           ▼
┌─────────────────────────┐
│ Elasticsearch           │
└──────────┬──────────────┘
           │ Index
           ▼
     batch-events-000001
```

---

## Configuration Management

### File Structure

```
elastic-agent/
├── elastic-agent.linux.yml.j2        # Jinja2 template for Linux hosts
├── elastic-agent.windows.yml         # Windows configuration (future)
├── elastic-agent.local.yml           # Local client testing
├── elastic_agent_env_systemd.conf    # Environment variables
└── docs/
    └── Elastic_Agent_Architecture.md # This document

ansible/
├── host_vars/
│   ├── Lab1.yml                      # Lab1-specific variables
│   └── Lab2.yml                      # Lab2-specific variables
└── playbooks/
    └── elastic-agent/
        └── install.yml                # Deployment playbook
```

### Template Variables

**Default Values (in template):**
```jinja2
spark_events_enabled: {{ spark_events_enabled | default('true') }}
spark_app_logs_enabled: {{ spark_app_logs_enabled | default('true') }}
spark_gc_logs_enabled: {{ spark_gc_logs_enabled | default('true') }}
spark_app_logs_ignore_older: {{ spark_app_logs_ignore_older | default('24h') }}
```

**Host-Specific Overrides (in host_vars/):**

**Lab1:**
```yaml
spark_events_enabled: false  # ← Prevents duplicate event collection
spark_app_logs_enabled: true
spark_gc_logs_enabled: true
spark_app_logs_ignore_older: "24h"
```

**Lab2:**
```yaml
spark_events_enabled: true   # ← NFS server collects events
spark_app_logs_enabled: true
spark_gc_logs_enabled: true
spark_app_logs_ignore_older: "24h"
```

### Deployment Process

1. Ansible reads `host_vars/<hostname>.yml`
2. Variables are passed to Jinja2 template
3. Template is rendered with host-specific values
4. Rendered config is deployed to `/opt/Elastic/Agent/elastic-agent.yml`
5. Agent service is restarted

**Command:**
```bash
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/elastic-agent/install.yml \
  -l Lab1,Lab2
```

---

## Data Destinations

### Elasticsearch (Default Output)

**Purpose:** Primary data store for metrics and logs  
**URL:** `https://GaryPC.local:9200`  
**Auth:** Certificate-based (CA: `/etc/ssl/certs/elastic/ca.crt`)

**Receives:**
- System metrics
- Spark application logs
- Spark GC logs

**Configuration:**
```yaml
outputs:
  default:
    type: elasticsearch
    hosts: ["${ELASTIC_URL}"]
    username: "${ELASTIC_USER}"
    password: "${ELASTIC_PASSWORD}"
    ssl:
      certificate_authorities: ["${CA_CERT_LINUX_PATH}"]
      verification_mode: full
```

### Logstash (Spark Events Output)

**Purpose:** Complex JSON transformation for Spark events  
**URL:** `GaryPC.local:5050`  
**Protocol:** Plain TCP (within trusted network)

**Receives:**
- Spark event logs (NDJSON)

**Processing:**
- Parse NDJSON format
- Extract event type and metadata
- Normalize timestamps
- Enrich with application context
- Route to Elasticsearch

**Configuration:**
```yaml
outputs:
  spark_events:
    type: logstash
    hosts: ["${LS_HOST}:${LS_SPARK_EVENTS_PORT}"]
```

**Logstash Pipeline:**
```ruby
input {
  beats {
    port => 5050
  }
}

filter {
  json {
    source => "message"
    target => "spark"
  }
  # ... additional transformations
}

output {
  elasticsearch {
    hosts => ["https://es01:9200"]
    index => "batch-events-%{+YYYY.MM.dd}"
  }
}
```

---

## Preventing Duplicate Collection

### The Problem

**Scenario:**
- Lab2 hosts NFS share: `/srv/nfs/spark/events`
- Lab1 mounts via NFS: `Lab2:/srv/nfs/spark/events → /mnt/spark/events`
- Both agents have filestream input monitoring `/mnt/spark/events/app-*`
- **Result:** Every event is collected and sent TWICE ❌

### The Solution

**Strategy: Conditional Input Enabling**

1. **Identify NFS Server:** Lab2 (hosts `/srv/nfs/spark/events`)
2. **Disable on Clients:** Lab1 (mounts via NFS)
3. **Enable on Server:** Lab2 only

**Implementation:**

**Template (`elastic-agent.linux.yml.j2`):**
```yaml
- id: spark-events
  enabled: {{ spark_events_enabled | default('true') }}
```

**Variables (`host_vars/Lab1.yml`):**
```yaml
spark_events_enabled: false  # NFS client - don't collect
```

**Variables (`host_vars/Lab2.yml`):**
```yaml
spark_events_enabled: true   # NFS server - collect once
```

### Verification

**Check Deployed Config:**
```bash
# Lab1 - should show "enabled: false"
ansible Lab1 -m shell -a "grep -A 3 'id: spark-events' /opt/Elastic/Agent/elastic-agent.yml"

# Lab2 - should show "enabled: true"
ansible Lab2 -m shell -a "grep -A 3 'id: spark-events' /opt/Elastic/Agent/elastic-agent.yml"
```

**Check Elasticsearch:**
```bash
# Should see events only from Lab2
curl -k -u elastic:pass https://GaryPC.local:9200/batch-events-*/_search \
  -d '{"aggs": {"by_host": {"terms": {"field": "host.name"}}}}'

# Expected result: Only "lab2" in aggregation
```

### Future: Direct Event Streaming

**Current Approach (Interim):**
- Spark writes events to files
- Filebeat collects files
- Logstash processes JSON

**Future Approach (Best Practice):**
- Spark `ListenerBus` sends events directly to Logstash
- No file intermediary
- Real-time event processing
- No duplication risk

**Implementation:**
1. Create custom `SparkListener` implementation
2. Configure to send events via HTTP/TCP to Logstash
3. Disable file-based event logging
4. Remove filestream input from Elastic Agent

---

## Deployment

### Prerequisites

1. **NFS Configuration:**
   ```bash
   ansible-playbook -i ansible/inventory.yml \
     ansible/playbooks/nfs/install.yml
   ```

2. **Elasticsearch CA Certificate:**
   - Distributed from: `/mnt/c/Volumes/certs/Elastic/ca.crt` (GaryPC)
   - Deployed to: `/etc/ssl/certs/elastic/ca.crt` (Lab1, Lab2)

3. **Environment Variables:**
   - Defined in: `ansible/vars/spark_vars.yml`
   - Generated by: `linux/generate_env.py`
   - Deployed via: `elastic_agent_env_systemd.conf`

### Installation

**Step 1: Deploy Configuration**
```bash
cd /home/gxbrooks/repos/elastic-on-spark/ansible
ansible-playbook playbooks/elastic-agent/install.yml -l Lab1,Lab2
```

**Step 2: Verify Status**
```bash
ansible-playbook playbooks/elastic-agent/status.yml
```

**Expected Output:**
```
Lab1: HEALTHY - spark_events disabled
Lab2: HEALTHY - spark_events enabled
```

**Step 3: Check Data Flow**
```bash
# System metrics (both hosts)
curl -k -u elastic:pass https://GaryPC.local:9200/_cat/indices/metrics-system*

# Spark app logs (both hosts)
curl -k -u elastic:pass https://GaryPC.local:9200/.ds-logs-spark-default*/_count

# Spark events (Lab2 only)
curl -k -u elastic:pass https://GaryPC.local:9200/batch-events-*/_count
```

### Configuration Updates

**Updating Single Host:**
```bash
# Edit host_vars if needed
vim ansible/host_vars/Lab1.yml

# Redeploy
ansible-playbook playbooks/elastic-agent/install.yml -l Lab1
```

**Template Changes:**
```bash
# Edit template
vim elastic-agent/elastic-agent.linux.yml.j2

# Deploy to all hosts
ansible-playbook playbooks/elastic-agent/install.yml -l native
```

---

## Monitoring & Troubleshooting

### Agent Health

**Check Status:**
```bash
ansible Lab1,Lab2 -m shell -a "sudo /opt/Elastic/Agent/elastic-agent status"
```

**Healthy Output:**
```
State: HEALTHY
Message: Running
```

**Degraded States:**
- `DEGRADED` - One or more inputs failing
- `FAILED` - Agent cannot start
- `STOPPED` - Not enrolled (expected for standalone mode)

### Common Issues

#### 1. Certificate Errors

**Symptom:**
```
x509: certificate signed by unknown authority
```

**Solution:**
```bash
# Update certificate on managed nodes
ansible Lab1,Lab2 -m copy \
  -a "src=/mnt/c/Volumes/certs/Elastic/ca.crt dest=/etc/ssl/certs/elastic/ca.crt" \
  --become

# Restart agents
ansible Lab1,Lab2 -m systemd \
  -a "name=elastic-agent state=restarted" \
  --become
```

#### 2. YAML Indentation Errors

**Symptom:**
```
yaml: line 10: did not find expected key
```

**Solution:**
```bash
# Validate YAML
yamllint elastic-agent/elastic-agent.linux.yml.j2

# Common fix: metricsets need 2 more spaces of indentation
```

#### 3. Duplicate Event Collection

**Symptom:**
```bash
# Same event appears twice in Elasticsearch
curl ... | jq '.hits.hits[] | ._source.event_id' | sort | uniq -d
```

**Diagnosis:**
```bash
# Check which hosts are collecting
ansible Lab1,Lab2 -m shell \
  -a "grep -A 3 'id: spark-events' /opt/Elastic/Agent/elastic-agent.yml | grep enabled"

# Expected:
# Lab1: enabled: false
# Lab2: enabled: true
```

**Solution:**
```bash
# Verify host_vars are correct
cat ansible/host_vars/Lab1.yml  # spark_events_enabled: false
cat ansible/host_vars/Lab2.yml  # spark_events_enabled: true

# Redeploy if needed
ansible-playbook playbooks/elastic-agent/install.yml -l Lab1,Lab2
```

#### 4. No Data Flowing

**Check Data Stream:**
```bash
# List all data streams
curl -k -u elastic:pass https://GaryPC.local:9200/_data_stream

# Check document counts
curl -k -u elastic:pass https://GaryPC.local:9200/_cat/indices/metrics-*,logs-*
```

**Check Agent Logs:**
```bash
ansible Lab2 -m shell \
  -a "sudo tail -100 /var/log/elastic-agent/elastic-agent-*.ndjson | grep -i error"
```

**Check Filebeat Registry:**
```bash
# See what files are being tracked
ansible Lab2 -m shell \
  -a "sudo find /opt/Elastic/Agent/data -name 'log.json' | xargs ls -lh"
```

### Performance Monitoring

**Agent Resource Usage:**
```bash
ansible Lab1,Lab2 -m shell -a "ps aux | grep elastic-agent | grep -v grep"
```

**Data Volume:**
```bash
# Events per day
curl -k -u elastic:pass https://GaryPC.local:9200/batch-events-*/_count

# Metrics per hour
curl -k -u elastic:pass https://GaryPC.local:9200/metrics-system.*/_search \
  -d '{"aggs": {"by_hour": {"date_histogram": {"field": "@timestamp", "interval": "1h"}}}}'
```

---

## Future Enhancements

### 1. Direct Event Streaming

**Goal:** Replace file-based event collection with direct streaming

**Approach:**
- Implement custom Spark `EventLoggingListener`
- Stream events via HTTP/gRPC to Logstash
- Remove file intermediary
- Eliminate duplication risk entirely

**Benefits:**
- Real-time event processing
- No file I/O overhead
- Simplified architecture
- No NFS dependency for events

### 2. Kubernetes Metrics

**Goal:** Enable comprehensive K8s monitoring

**Requirements:**
- Proper RBAC configuration
- Kubeconfig distribution
- Resource filtering (focus on Spark namespace)

### 3. Multi-Cluster Support

**Goal:** Support multiple Spark clusters

**Approach:**
- Cluster-specific namespaces in data streams
- Cluster identifier in all events
- Centralized vs. per-cluster collection strategies

### 4. Dynamic Configuration

**Goal:** Hot-reload configuration without restart

**Approach:**
- Use Elasticsearch as configuration backend
- Agents poll for config changes
- Apply changes without service interruption

---

## Appendix

### A. Directory Structure

```
/mnt/spark/
├── events/              # NFS-shared (Lab2 server, Lab1 client)
│   ├── app-*           # Spark event logs (NDJSON)
│   └── .inprogress     # Temp files (excluded)
├── logs/               # Per-host (symlinks to kubelet)
│   ├── spark-master-0/
│   │   ├── spark-app.log
│   │   └── gc-master.log
│   ├── spark-worker-lab1-*/
│   │   ├── spark-app.log
│   │   └── gc-executor.log
│   └── spark-worker-lab2-*/
│       ├── spark-app.log
│       └── gc-executor.log
└── data/               # NFS-shared (workdir, checkpoints)
```

### B. Input IDs Reference

| Input ID | Type | Purpose | Enabled On |
|----------|------|---------|------------|
| `system-metrics-input` | system/metrics | Host metrics | All hosts |
| `spark-events` | filestream | Event logs | Lab2 only |
| `spark-app-logs` | filestream | Application logs | All hosts |
| `spark-gc` | filestream | GC logs | All hosts |
| `kubernetes-metrics` | kubernetes/metrics | K8s metrics | Disabled |

### C. Data Stream Patterns

| Pattern | Type | Description |
|---------|------|-------------|
| `metrics-system.*-default` | Metrics | System metrics by type |
| `logs-spark-default` | Logs | Spark application logs |
| `logs-spark_gc-default` | Logs | Spark GC logs |
| `batch-events-*` | Events | Spark execution events |

### D. Key Configuration Files

| File | Purpose | Templated |
|------|---------|-----------|
| `elastic-agent.linux.yml.j2` | Main agent config | Yes |
| `elastic_agent_env_systemd.conf` | Environment variables | No |
| `host_vars/Lab1.yml` | Lab1-specific vars | No |
| `host_vars/Lab2.yml` | Lab2-specific vars | No |
| `install.yml` | Deployment playbook | No |

---

**Document History:**
- v1.0 (2025-11-12): Initial documentation covering all four telemetry types

**Related Documents:**
- `../tmp/Elastic_Agent_Config_Consolidation_Plan.md` - Migration from per-host to OS-based configs
- `../../docs/Log_Architecture.md` - Overall logging architecture
- `../../docs/CA_CERTIFICATE_ARCHITECTURE.md` - Certificate management

