# Log Architecture for Spark-on-Kubernetes Observability

## Overview

This document outlines the comprehensive logging architecture for Spark applications running on Kubernetes, with Elastic Agent collecting and processing logs for observability. The architecture implements file-based logging with pod-specific directories to prevent conflicts and enable rich metadata tagging.

## Core Principles

1. **File-Based Logging**: All Spark components write GC and application logs to files for better parsing and separation
2. **Pod-Specific Directories**: Use unique log directories per pod to prevent filename conflicts
3. **Elastic Agent Best Practices**: Follow Kubernetes-native patterns for log collection
4. **Java 11 Unified Logging**: Leverage simplified GC log format for easier processing
5. **Rich Metadata**: Comprehensive tagging for filtering and analysis in Kibana

## Spark Application Logging

### Architecture by Deployment Mode

#### **Client Mode (Development - Chapter_04.py)**

When running Spark applications locally that connect to a remote Kubernetes cluster:

**Driver Configuration** (`spark/conf/spark-defaults.conf`):
```properties
# Driver runs locally - basic GC only (not monitored)
spark.driver.extraJavaOptions          -XX:+UseG1GC -Xlog:gc*:file=/tmp/spark-driver-gc.log:time,uptime,level,tags:filecount=10,filesize=10M
# Executors run in Kubernetes - both GC and app logs to pod-specific directories
spark.executor.extraJavaOptions        -XX:+UseG1GC -Xlog:gc*:file=/opt/spark/logs/gc-executor.log:time,uptime,level,tags:filecount=10,filesize=10M -Dlog4j2.configurationFile=file:///opt/spark/conf/log4j2-executor.properties
```

**Executor Configuration** (Kubernetes ConfigMap from `spark-defaults.conf.j2`):
```properties
# Executors run in Kubernetes - file-based logging with rotation
spark.executor.extraJavaOptions        -XX:+UseG1GC -Xlog:gc*:file=/opt/spark/logs/gc-executor.log:time,uptime,level,tags:filecount=10,filesize=10M -Dlog4j2.configurationFile=file:///opt/spark/conf/log4j2-executor.properties
```

**Log Flow** (Pod-Specific Directory Strategy):
```
Local Machine (Driver)                    Kubernetes Cluster (Executors)
├── Driver JVM                           ├── Executor JVMs (in pods)
│   ├── GC logs → /tmp/spark-driver-gc.log │   ├── GC logs → /opt/spark/logs/gc-executor.log
│   └── (Not monitored)                  │   ├── App logs → /opt/spark/logs/executor-app.log
└── No Elastic Agent needed              │   │            ↓ (mounted to host)
                                         │   │   /mnt/spark/logs/{pod-name}/ (host)
                                         │   │   ├── spark-worker-lab2-abc123/
                                         │   │   │   ├── gc-executor.log
                                         │   │   │   └── executor-app.log
                                         │   │   └── spark-worker-lab2-def456/
                                         │   │       ├── gc-executor.log
                                         │   │       └── executor-app.log
                                         └── Elastic Agent (on K8s hosts) → Elasticsearch
```

**Key Insight**: In client mode, **only executor logs matter for observability**. Driver logs are local development artifacts and should not be part of production monitoring.

### Deployment Architecture

#### **Physical Infrastructure**

```
┌─────────────────────────┐    ┌─────────────────────────────────────────┐
│ Local Development       │    │ Kubernetes Host Machines (Lab1, Lab2)   │
│ Machine (gxbrooks)      │    │                                         │
│                         │    │ ┌─────────────────────────────────────┐ │
│ ├── Python Process      │    │ │ Host OS (Ubuntu/Linux)              │ │
│ │   └── Chapter_04.py   │    │ │                                     │ │
│ ├── Driver JVM          │    │ │ ├── Elastic Agent (host process)   │ │
│ │   └── Console logs    │    │ │ │   └── Reads /var/log/pods/       │ │
│ │       (not monitored) │    │ │                                     │ │
│ └── No Elastic Agent    │    │ │ ├── Kubernetes Runtime             │ │
└─────────────────────────┘    │ │ │   ├── kubelet                    │ │
                               │ │ │   ├── Container runtime          │ │
                               │ │ │   └── Pod logs → /var/log/pods/  │ │
                               │ │ │                                   │ │
                               │ │ └── Kubernetes Pods                │ │
                               │ │     ├── Spark Master Pod           │ │
                               │ │     ├── Spark Worker Pods          │ │
                               │ │     │   └── Executor JVMs           │ │
                               │ │     │       ├── GC logs → stdout   │ │
                               │ │     │       └── App logs → stdout  │ │
                               │ │     └── Other K8s services         │ │
                               │ └─────────────────────────────────────┐ │
                               └─────────────────────────────────────────┘
```

#### **Log Flow Architecture**

```
┌─────────────────────────┐    ┌─────────────────────────────────────────┐
│ Local Development       │    │ Kubernetes Host (Lab1, Lab2)            │
│                         │    │                                         │
│ Driver JVM              │    │ Executor JVMs (in pods)                 │
│ ├── GC logs → console   │    │ ├── GC logs → stdout                    │
│ └── App logs → console  │    │ └── App logs → stdout                   │
│     (development only)  │    │         ↓                               │
│                         │    │ Container Runtime                       │
│ No monitoring needed    │    │ ├── Captures stdout/stderr              │
│                         │    │ └── Writes to /var/log/pods/            │
│                         │    │         ↓                               │
│                         │    │ Host OS                                 │
│                         │    │ ├── /var/log/pods/spark_*/*/*.log       │
│                         │    │ └── Elastic Agent (host process)       │
│                         │    │         ↓                               │
│                         │    │ Elasticsearch Cluster                   │
│                         │    │ └── Observability & Monitoring          │
└─────────────────────────┘    └─────────────────────────────────────────┘
```

#### **Key Architecture Points**

1. **Elastic Agent Deployment**: Runs as **host processes** on Kubernetes nodes (Lab1, Lab2), not inside pods
2. **Log Access**: Elastic Agent reads `/var/log/pods/` from the **host filesystem**
3. **Container Isolation**: Executor logs written to stdout are captured by container runtime and stored on host
4. **Network Separation**: Local development machine connects to Kubernetes cluster but doesn't participate in log collection
5. **Observability Boundary**: Only distributed workload (executors) is monitored, not local development processes

### Kubernetes Volume Mount Strategy

#### **Best Practice: Pod-Specific Directory Strategy**

**Problem Solved**: Multiple pods of the same type (e.g., workers) writing to the same log file causes conflicts and data corruption.

**Solution**: Use the same naming strategy as `/var/log/pods/*` but in `/mnt/spark/logs/`:

**Directory Pattern**: `/mnt/spark/logs/{namespace}_{podname}_{uid}/`

**Kubernetes Configuration** (`spark-worker.yaml.j2`):
```yaml
# Init container creates pod-specific directory
initContainers:
  - name: setup-logs
    image: "docker.io/apache/spark:3.5.1"
    command: ['sh', '-c', 'mkdir -p /mnt/spark/logs/${POD_NAMESPACE}_${POD_NAME}_${POD_UID} && chown -R spark:spark /mnt/spark/logs/${POD_NAMESPACE}_${POD_NAME}_${POD_UID}']
    securityContext:
      runAsUser: 0
    env:
      - name: POD_NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: POD_NAME
        valueFrom:
          fieldRef:
            fieldPath: metadata.name
      - name: POD_UID
        valueFrom:
          fieldRef:
            fieldPath: metadata.uid

# Main container uses shell script to expand environment variables
containers:
  - name: spark-worker
    command: ["/bin/bash", "-c"]
    args: 
      - |
        export SPARK_WORKER_OPTS="-XX:+UseG1GC -Xlog:gc*:/mnt/spark/logs/${POD_NAMESPACE}_${POD_NAME}_${POD_UID}/worker-gc.log:time,tags"
        exec /opt/spark/sbin/start-worker.sh

volumeMounts:
  - name: spark-logs-host
    mountPath: /mnt/spark/logs
volumes:
  - name: spark-logs-host
    hostPath:
      path: /mnt/spark/logs
      type: DirectoryOrCreate
```

#### **Volume Mount Options Analysis**

| Approach | Path | Pros | Cons | Recommendation |
|----------|------|------|------|----------------|
| **Dedicated Host Path** | `/opt/spark/logs` → `/mnt/spark/logs` | ✅ Clean separation<br/>✅ Predictable paths<br/>✅ Follows existing pattern | ❌ Additional volume | **RECOMMENDED** |
| **Extend Work Directory** | `/opt/spark/work/logs/` | ✅ Uses existing mount<br/>✅ No new volume | ❌ Mixed concerns<br/>❌ Less organized | Alternative |
| **Use `/var/log/pods/`** | `/opt/spark/logs` → `/var/log/pods/...` | ❌ Dynamic paths<br/>❌ Kubernetes conflicts<br/>❌ Non-standard | ❌ Many issues | **NOT RECOMMENDED** |

#### **Current Volume Mount Architecture**

```
Container Paths                    Host Paths
├── /mnt/spark/events      →      /mnt/spark/events (Spark events)
├── /mnt/spark/data        →      /mnt/spark/data (Data files)
├── /opt/spark/work        →      /mnt/spark/work (Work directory)
└── /opt/spark/logs        →      /mnt/spark/logs (Application logs) ← NEW
```

#### **Conflict Resolution: Pod-Specific Subdirectories**

**The Problem:**
Multiple executor pods writing to the same log file path would cause conflicts:
```
Pod spark-worker-lab1-abc123 → /opt/spark/logs/executor-gc.log → /mnt/spark/logs/executor-gc.log ← CONFLICT!
Pod spark-worker-lab1-def456 → /opt/spark/logs/executor-gc.log → /mnt/spark/logs/executor-gc.log ← CONFLICT!
```

**The Solution:**
Use `${HOSTNAME}` environment variable to create pod-specific subdirectories:
```
Pod spark-worker-lab1-abc123 → /opt/spark/logs/spark-worker-lab1-abc123/
                            │   ├── executor-gc.log
                            │   └── executor-app.log
                            → /mnt/spark/logs/spark-worker-lab1-abc123/ ✅
                                ├── executor-gc.log
                                └── executor-app.log

Pod spark-worker-lab1-def456 → /opt/spark/logs/spark-worker-lab1-def456/
                            │   ├── executor-gc.log  
                            │   └── executor-app.log
                            → /mnt/spark/logs/spark-worker-lab1-def456/ ✅
                                ├── executor-gc.log
                                └── executor-app.log
```

**Elastic Agent Configuration:**
```yaml
# GC Logs Input - Java 11 format is MUCH simpler!
- id: spark-gc
  paths:
    - '/mnt/spark/logs/*/executor-gc.log*'
  processors:
    # Single dissect pattern handles entire Java 11 G1GC log format
    - dissect:
        tokenizer: "[%{gc_timestamp}][%{gc_tags}] GC(%{cycle|integer}) Pause %{type} (%{kind}) %{before|integer}M->%{after|integer}M(%{heapsize|integer}M) %{millis|float}ms"
        target_prefix: gc.paused
    - dissect:
        tokenizer: "/mnt/spark/logs/%{pod_name}/executor-gc.log"
        target_prefix: spark
    # Preserve ingestion time for latency measurement
    - add_fields:
        target: gc
        fields:
          ingest_time: "@timestamp"
    # Use GC event time as primary timestamp
    - timestamp:
        field: gc.paused.gc_timestamp
        target_field: "@timestamp"

# Application Logs Input  
- id: spark-app-logs
  paths:
    - '/mnt/spark/logs/*/executor-app.log*'
  processors:
    - dissect:
        tokenizer: "/mnt/spark/logs/%{pod_name}/executor-app.log"
        target_prefix: spark
```

**Benefits:**
- ✅ **No conflicts**: Each pod writes to its own subdirectory
- ✅ **Pod identification**: Pod name extracted from file path  
- ✅ **Consistent approach**: Both GC and app logs use same mount strategy
- ✅ **Distinct file patterns**: `executor-gc.log` vs `executor-app.log`
- ✅ **No container log mixing**: Avoids `/var/log/pods/` entirely
- ✅ **Clean separation**: Different inputs for different log types
- ✅ **Scalable**: Works with any number of executor pods
- ✅ **Simplified processing**: Java 11 GC format eliminates complex parsing

### **Java 11 GC Processing Simplification**

**Major Improvement**: Java 11's unified GC logging format (`-Xlog:gc*`) is **dramatically simpler** than legacy formats!

**Old Complex Processing** (Java 8/Legacy):
- Required 50+ lines of complex conditional dissect processors
- Multiple `if/then/else` chains for different GC types
- Separate handling for "Young", "Remark", "Cleanup" collections
- Complex regex patterns and fallback logic

**New Simple Processing** (Java 11):
- **Single dissect pattern** handles all pause events
- Consistent format: `[timestamp][gc] GC(cycle) Pause Type (Kind) BeforeM->AfterM(HeapM) TimeMs`
- All required fields extracted in one operation
- No conditional logic needed

**Example Java 11 Log Entry**:
```
[2025-10-02T10:53:15.764-0500][gc] GC(9) Pause Full (System.gc()) 1M->0M(40M) 0.674ms
```

**Extracted Fields**:
- `gc.paused.cycle`: `9`
- `gc.paused.type`: `Full`
- `gc.paused.kind`: `System.gc()`
- `gc.paused.before`: `1` (MB)
- `gc.paused.after`: `0` (MB)
- `gc.paused.heapsize`: `40` (MB)
- `gc.paused.millis`: `0.674` (ms)

This provides **all the pause time and heap utilization data** needed for GC performance analysis with minimal processing overhead.

## Summary

### **Complete Logging Architecture Implementation**

This document describes a comprehensive logging architecture for Spark-on-Kubernetes deployments that provides:

1. **File-Based Logging**: All Spark components (master, workers, history server, executors) write GC and application logs to files with rotation
2. **Pod-Specific Directories**: Unique log directories prevent conflicts between multiple pods using `{pod-name}` pattern
3. **Elastic Agent Best Practices**: Follows Kubernetes-native patterns with system metrics, system logs, and Kubernetes metrics
4. **Java 11 Unified Logging**: Simplified GC log processing using modern Java logging format
5. **Rich Metadata**: Comprehensive tagging for filtering and analysis in Kibana

### **Key Benefits**

- **🔍 Enhanced Observability**: Complete visibility into Spark component performance
- **📊 Rich Metadata**: Filter and group logs by host, namespace, pod, and Spark role
- **🚫 No Conflicts**: Pod-specific directories prevent log file collisions
- **⚡ Performance**: File-based logging with minimal overhead
- **🔧 Troubleshooting**: Easy identification of specific components and issues
- **🏗️ Best Practices**: Follows Elastic's recommended deployment patterns

### **Production Ready**

All components have been tested and verified:
- ✅ Master, Worker, History Server, and Executor logging
- ✅ Pod-specific directory strategy preventing conflicts
- ✅ Java 11 unified GC logging format with rotation
- ✅ Elastic Agent best practices implementation
- ✅ Process IO errors resolved
- ✅ System metrics and logs collection

The architecture is now **production-ready** for comprehensive Spark observability! 🚀

## Metadata Tagging Strategy

### **Overview**

To provide comprehensive observability across both Kubernetes and Docker Compose deployments, all Spark logs are enriched with standardized metadata fields. This enables consistent filtering, grouping, and analysis regardless of the deployment environment.

### **Metadata Fields**

**Universal Fields (Available in all deployments):**
- `spark.metadata.host` - Physical/virtual host running the component
- `spark.metadata.deployment_type` - Either "kubernetes" or "docker-compose"
- `spark.metadata.spark_role` - Normalized Spark role (master, worker, history-server, executor, driver)
- `spark.component_type` - Raw component type extracted from log file path

**Kubernetes-Specific Fields:**
- `spark.metadata.namespace` - Kubernetes namespace
- `spark.metadata.pod_name` - Full pod name including replica set hash
- `spark.metadata.pod_uid` - Unique pod identifier

**Docker Compose-Specific Fields:**
- `spark.metadata.service_name` - Docker Compose service name
- `spark.metadata.instance_id` - Container instance identifier

### **Implementation Strategy**

The metadata enrichment uses a multi-stage approach:

1. **Path Parsing**: Extract pod/container directory and component type from log file path
2. **Environment Detection**: Parse directory name using both Kubernetes (`namespace_podname_uid`) and Docker Compose (`service_instance`) patterns
3. **Metadata Normalization**: Use Painless script to create consistent `spark.metadata.*` fields
4. **Role Mapping**: Normalize component types to standard Spark roles

### **Kibana Integration**

All metadata fields are automatically included in the Spark GC data view with human-readable labels:
- **Host** → Physical host identifier
- **Deployment Type** → Kubernetes or Docker Compose
- **Kubernetes Namespace** → K8s namespace
- **Pod Name** → Full Kubernetes pod name
- **Spark Role** → Normalized Spark component role

This enables powerful filtering and visualization capabilities in Kibana dashboards.

## Implementation Verification

### **Current Status (October 2, 2025)**

All log changes have been successfully implemented using the **template approach**:

#### **✅ Spark Components Logging**
- **Master Daemon**: `/mnt/spark/logs/spark_spark-master-0_{uid}/master-gc.log` (pod-specific directories)
- **Worker Daemons**: `/mnt/spark/logs/spark_spark-worker-*_{uid}/worker-gc.log` (pod-specific directories)
- **History Server**: `/mnt/spark/logs/spark_spark-history-*_{uid}/history-gc.log` (pod-specific directories)
- **Executors**: `/mnt/spark/logs/executor-gc-%t.log` (timestamp-based, simple directory structure)

#### **✅ Template-Based Configuration**
- **Template Approach**: Using `ansible/roles/spark/templates/spark-defaults.conf.j2` for Kubernetes components
- **Client Configuration**: `spark/conf/spark-defaults.conf` for local driver only
- **No Environment Variables**: Executors use simple timestamp-based naming to avoid expansion issues

#### **✅ Java 11 Unified GC Logging**
- **Format**: `GC(cycle) Pause Type (Kind) BeforeM->AfterM(HeapM) TimeMs`
- **G1GC**: All components using G1 garbage collector
- **File-Based**: No more stdout logging for production observability

#### **✅ Configuration Updates**
- **Template**: Updated with correct executor GC logging path
- **ConfigMaps**: Updated and deployed to Kubernetes
- **Elastic Agent**: Enhanced with comprehensive metadata tagging

### **Verification Commands**

```bash
# Check master GC logs
ls -la /mnt/spark/logs/spark_spark-master-*/master-gc.log

# Check worker GC logs  
kubectl exec spark-worker-* -n spark -- ls -la /mnt/spark/logs/spark_spark-worker-*/worker-gc.log

# Check history server GC logs
ls -la /mnt/spark/logs/spark_spark-history-*/history-gc.log

# Check executor GC logs
ls -la /mnt/spark/logs/executor-gc-*.log*

# Verify GC log content
tail -3 /mnt/spark/logs/spark_spark-master-*/master-gc.log
grep "Pause" /mnt/spark/logs/executor-gc-*.log | head -3
```

### **Template Configuration Details**

The executor GC logging is configured in `ansible/roles/spark/templates/spark-defaults.conf.j2`:

```yaml
# JVM options for GC logging and application logging
# All Spark components (master, worker, history server) write logs to mounted directories
# Pod-specific subdirectories prevent conflicts between multiple pods on same host
spark.executor.extraJavaOptions        -XX:+UseG1GC -Xlog:gc*:/mnt/spark/logs/executor-gc-%t.log:time,tags -Dlog4j2.configurationFile=file:///opt/spark/conf/log4j2-executor.properties
spark.driver.extraJavaOptions          -XX:+UseG1GC -Xlog:gc*:/mnt/spark/logs/${HOSTNAME}/driver-gc.log:time,tags -Dlog4j2.configurationFile=file:///opt/spark/conf/log4j2-kubernetes.properties
```

**Key Points:**
- **Executors**: Use simple timestamp-based naming (`%t`) to avoid environment variable expansion issues
- **Drivers**: Use `${HOSTNAME}` expansion for pod-specific directories (works in daemon processes)
- **Template Approach**: Ensures consistent configuration across all Kubernetes components

### **Pending Items**

1. **Elastic Agent Restart** (requires sudo):
   ```bash
   sudo systemctl restart elastic-agent
   ```

2. **Verify Metadata Fields** (after restart):
   ```bash
   curl -k -u elastic:myElastic2025 -s "https://localhost:9200/.ds-logs-spark-*/_search?size=1&sort=@timestamp:desc&_source=spark.metadata"
   ```

## GC Logs Processing

### **Overview**

Garbage Collection (GC) logs are critical for understanding Spark executor performance, memory pressure, and pause times that can impact job execution. Our architecture focuses on collecting GC logs from Kubernetes-based executors for observability.

### **GC Log Configuration**

**Executor GC Logging** (`spark-defaults.conf`):
```properties
# Executors write GC logs to pod-specific mounted directories
spark.executor.extraJavaOptions  -XX:+UseG1GC -Xlog:gc*:/opt/spark/logs/${HOSTNAME}/executor-gc.log:time,tags
```

**Key Configuration Details**:
- **G1GC**: Uses G1 Garbage Collector for predictable pause times
- **Java 11 Format**: `-Xlog:gc*` provides unified, consistent log format
- **Pod-Specific Paths**: `${HOSTNAME}` creates unique directories per executor
- **Time & Tags**: Includes timestamps and GC event tags for parsing

### **Log Format & Processing**

**Java 11 GC Log Format**:
```
[2025-10-02T10:53:15.764-0500][gc] GC(9) Pause Full (System.gc()) 1M->0M(40M) 0.674ms
```

**Elastic Agent Processing**:
```yaml
- dissect:
    tokenizer: "[%{gc_timestamp}][%{gc_tags}] GC(%{cycle|integer}) Pause %{type} (%{kind}) %{before|integer}M->%{after|integer}M(%{heapsize|integer}M) %{millis|float}ms"
    target_prefix: gc.paused
```

**Extracted Fields**:
- `gc.paused.cycle`: GC cycle number
- `gc.paused.type`: Collection type (Young, Full, etc.)
- `gc.paused.kind`: Collection reason (System.gc, Allocation Failure, etc.)
- `gc.paused.before`: Heap usage before GC (MB)
- `gc.paused.after`: Heap usage after GC (MB)
- `gc.paused.heapsize`: Total heap size (MB)
- `gc.paused.millis`: Pause time in milliseconds

### **Timestamp Management**

**Dual Timestamp Strategy**:
```yaml
# Preserve original @timestamp as ingestion time for latency measurement
- add_fields:
    target: gc
    fields:
      ingest_time: "@timestamp"
# Use GC timestamp as the primary event timestamp
- timestamp:
    field: gc.paused.gc_timestamp
    target_field: "@timestamp"
```

**Purpose**:
- `@timestamp`: Actual GC event time (for accurate time-series analysis)
- `gc.ingest_time`: Elasticsearch ingestion time (for measuring transmission latency)

**Latency Calculation**:
```
transmission_latency = gc.ingest_time - @timestamp
```

### **Data Flow**

```
Kubernetes Executor Pod                    Host Machine                     Elasticsearch
├── GC Event occurs                       ├── Elastic Agent                ├── Index: logs-spark_gc-default
├── Write to executor-gc.log              ├── Reads mounted file           ├── Fields:
├── Mount: /opt/spark/logs/${HOSTNAME}/   ├── Processes with dissect       │   ├── @timestamp (GC event time)
└── File: executor-gc.log                 ├── Extracts pause metrics       │   ├── gc.ingest_time (ingestion time)
                                         └── Ships to Elasticsearch       │   ├── gc.paused.millis (pause time)
                                                                          │   ├── gc.paused.before/after (heap)
                                                                          │   └── spark.pod_name (executor ID)
```

### **Observability Benefits**

**Performance Metrics**:
- **Pause Times**: Track GC pause duration impact on job execution
- **Heap Utilization**: Monitor memory pressure and allocation patterns
- **Collection Frequency**: Identify excessive GC activity
- **Transmission Latency**: Measure log pipeline performance

**Alerting Capabilities**:
- High pause times (> 100ms)
- Frequent full GC collections
- Memory pressure indicators
- Log transmission delays

### **Java 11 Advantages**

**Simplified Processing**: Java 11's unified logging eliminates the complex conditional processing required for legacy GC formats:

- **Before**: 50+ lines of complex `if/then/else` processors
- **After**: Single dissect pattern handles all pause events
- **Reliability**: No complex conditionals to fail
- **Maintenance**: Single pattern to understand and modify

#### **Cluster Mode (Production - Full Kubernetes)**

When running Spark applications entirely within Kubernetes:

**Configuration** (Kubernetes ConfigMap):
```properties
# Both driver and executors run in Kubernetes - all logs go to stdout
spark.executor.extraJavaOptions        -XX:+UseG1GC -Xlog:gc*:stdout:time,tags
spark.driver.extraJavaOptions          -XX:+UseG1GC -Xlog:gc*:stdout:time,tags
```

**Log Flow**:
```
Kubernetes Cluster (Both Driver & Executors)
├── Driver JVM (in pod) → stdout → /var/log/pods/
├── Executor JVMs (in pods) → stdout → /var/log/pods/
└── Elastic Agent (on K8s hosts) → Elasticsearch
```

### Elastic Agent Configuration

**File**: `elastic-agent/elastic-agent.linux.yml`

#### **Elastic Agent Best Practices Implementation**

**Host-Based Deployment** (Current Architecture):
```
Kubernetes Host Machine (Lab1/Lab2)
├── Host OS (Ubuntu/Linux)
│   ├── Elastic Agent Process
│   │   ├── System Metrics: CPU, memory, network, diskio, filesystem, load
│   │   ├── System Logs: /var/log/auth.log, /var/log/syslog
│   │   ├── Kubernetes Metrics: container, pod, node metrics
│   │   ├── Spark GC Logs: /mnt/spark/logs/*/gc-*.log*
│   │   ├── Spark App Logs: /mnt/spark/logs/*/executor-app.log*
│   │   └── Sends to: Elasticsearch cluster
│   └── File System Access: Direct host filesystem access
├── Kubernetes Runtime
│   ├── kubelet (manages pods)
│   ├── Container runtime (containerd/docker)
│   └── Pod log storage: /var/log/pods/
└── Kubernetes Pods
    ├── Spark Master Pod
    ├── Spark Worker Pods (with Executors)
    │   └── File-based logs → /mnt/spark/logs/{pod-name}/
    └── Other application pods
```

**Why Host-Based?**
1. **Direct filesystem access** to mounted log directories without volume mounts
2. **Persistent across pod restarts** - agent continues running when pods restart
3. **Lower resource overhead** - single agent per host vs per-pod agents
4. **Simplified networking** - direct access to Elasticsearch without pod networking complexity
5. **Centralized collection** - one agent collects logs from all pods on the host
6. **Kubernetes best practices** - follows Elastic's recommended deployment model

#### **Elastic Agent Input Configuration**

The Elastic Agent configuration implements best practices for Kubernetes deployments:

**System Metrics** (CPU, memory, network, diskio, filesystem, load):
- Process metrics explicitly disabled to avoid IO permission errors
- Follows Elastic's recommended system monitoring approach

**System Logs** (auth.log, syslog):
- Standard system log collection for security and system events
- Host-based collection for comprehensive system observability

**Kubernetes Metrics** (container, pod, node):
- Cluster-level metrics via kube-state-metrics
- Node-level metrics via Kubelet/cAdvisor
- Container runtime metrics

**Spark GC Logs** (file-based collection):
- Collects from pod-specific directories: `/mnt/spark/logs/*/gc-*.log*`
- Java 11 unified GC log format processing
- Rich metadata tagging with pod information
- Dual timestamp strategy for latency measurement

**Spark Application Logs** (file-based collection):
- Collects from pod-specific directories: `/mnt/spark/logs/*/executor-app.log*`
- Separate from GC logs for different processing pipelines
- Application-specific parsing and filtering

### Strengths

✅ **Architecture Awareness**: Correctly handles driver vs executor logging patterns  
✅ **Development Friendly**: Local driver logs for easy debugging  
✅ **Kubernetes Native**: Executor logs follow container best practices  
✅ **Separation of Concerns**: Driver and executor logs handled appropriately  
✅ **Direct File Access**: Driver logs parsed without container overhead  
✅ **Standard Container Logs**: Executor logs use proven Kubernetes patterns  

### Weaknesses

❌ **Dual Configuration**: Different logging approaches for driver vs executors  
❌ **Environment Dependency**: Local development requires file system setup  
❌ **Complex Elastic Agent**: Multiple input configurations needed  
❌ **Path Management**: Development paths need to be maintained  

## Docker Application Logging

### Current Architecture

**Configuration Location**: `observability/docker-compose.yml`

```yaml
services:
  elasticsearch:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

**Log Flow**:
```
Docker Container → stdout/stderr → Docker JSON Driver → /var/lib/docker/containers/ → Elastic Agent → Elasticsearch
```

### Elastic Agent Configuration

```yaml
- id: docker-logs
  type: filestream
  enabled: true
  paths:
    - '/var/lib/docker/containers/*/*.log'
  processors:
    - add_docker_metadata:
        host: "unix:///var/run/docker.sock"
```

### Strengths

✅ **Docker Native**: Uses standard Docker logging drivers  
✅ **Automatic Metadata**: Docker labels and container info  
✅ **Log Rotation**: Built-in size and file limits  
✅ **No Configuration**: Works out-of-the-box  

### Weaknesses

❌ **Host Filesystem**: Logs stored on Docker host  
❌ **Disk Space**: Can consume significant space  
❌ **Complex Paths**: Container ID-based directory structure  

### Alternative Approaches for Complex Paths

**Current**: `/var/lib/docker/containers/[container-id]/[container-id]-json.log`

**Better Approaches**:
1. **Docker Logging Drivers**: Use `journald`, `syslog`, or `fluentd` drivers for structured collection
2. **Log Aggregation**: Deploy Fluent Bit or Filebeat as DaemonSet for log forwarding
3. **Container Labels**: Use Docker labels to create more meaningful log routing
4. **Centralized Logging**: Forward logs directly to log aggregation services


## Setup Instructions

### Initial Setup

1. **Create log directories**:
   ```bash
   # For production (requires sudo)
   sudo mkdir -p /opt/spark/logs /opt/spark/gc-logs
   sudo chmod 755 /opt/spark/logs /opt/spark/gc-logs
   
   # For development
   mkdir -p ~/spark-logs/app ~/spark-logs/gc
   ```

2. **Configure Spark logging**:
   - Update `spark/conf/spark-defaults.conf` with GC log file paths
   - Update `spark/conf/log4j2.properties` with application log file paths

3. **Update Elastic Agent configuration**:
   - Add paths to `elastic-agent/elastic-agent.linux.yml`
   - Configure processors for direct log file parsing

4. **Test configuration**:
   ```bash
   # Run a Spark application
   python3 spark/apps/Chapter_04.py
   
   # Verify logs are created
   ls -la /opt/spark/logs/ /opt/spark/gc-logs/
   # or for development
   ls -la ~/spark-logs/app/ ~/spark-logs/gc/
   ```

### Host Mount Configuration

For production deployments, ensure log directories are mounted to the host:

```yaml
# Docker Compose example
volumes:
  - /host/spark-logs/app:/opt/spark/logs
  - /host/spark-logs/gc:/opt/spark/gc-logs

# Kubernetes example
volumes:
- name: spark-app-logs
  hostPath:
    path: /opt/spark/logs
- name: spark-gc-logs
  hostPath:
    path: /opt/spark/gc-logs
```

## Best Practices Summary

### For Spark Applications

1. **Understand deployment mode**: Client mode (driver local) vs Cluster mode (driver in K8s)
2. **Focus observability on executors**: Only executor logs matter for production monitoring
3. **Configure executor logging**: Always use stdout for Kubernetes container collection
4. **Minimize driver logging**: Basic GC only, no detailed logging for client mode
5. **Single Elastic Agent focus**: Monitor Kubernetes container logs only
6. **Separate concerns**: Development (local) vs Production (Kubernetes) logging

### For Docker Applications

1. **Use Docker logging drivers** (json-file, journald, etc.)
2. **Configure log rotation** to prevent disk space issues
3. **Leverage Docker metadata** for log enrichment
4. **Monitor disk usage** on Docker hosts

### For Elastic Agent

1. **Use simple path patterns** (e.g., `/var/log/pods/spark_*/*/*.log`)
2. **Handle mixed log formats** with conditional processors
3. **Set appropriate permissions** for log file access
4. **Use data streams** for different log types (app vs. GC)

## Future Improvements

- **Kubernetes DaemonSet**: Deploy Elastic Agent in Kubernetes for better integration
- **Log Aggregation**: Consider Fluent Bit or similar for log forwarding
- **Structured Logging**: Move to JSON-based application logs
- **Log Sampling**: Implement sampling for high-volume GC logs
- **Multi-tenancy**: Separate log streams by application/namespace
- **Alternative Docker Logging**: Implement journald or syslog drivers for better path management

## Troubleshooting

### Common Issues

1. **No GC logs in Elasticsearch**
   - Check if applications are generating GC activity
   - Verify Elastic Agent has access to `/var/log/pods/`
   - Confirm GC logging is enabled in Spark configuration

2. **Permission denied errors**
   - Ensure Elastic Agent user has read access to log directories
   - Check file ownership and permissions on log files
   - Verify Elastic Agent is running with appropriate user/group

3. **Missing log data**
   - Restart applications to generate fresh logs
   - Check Elasticsearch index patterns and retention policies
   - Verify container applications are writing to stdout/stderr

### Monitoring Commands

#### **Client Mode Development**
```bash
# Run Spark application (driver logs to console only)
python3 spark/apps/Chapter_04.py

# Verify no local log files created (correct behavior)
ls -la ~/spark-logs 2>/dev/null || echo "No local logs - correct!"

# Check executor activity via Spark UI
curl -s http://Lab2.lan:31472 | grep -i "Running Applications"
```

#### **Kubernetes Host Monitoring**
```bash
# On Kubernetes hosts (Lab1, Lab2) - check container logs
ls -la /var/log/pods/spark_*/

# Check specific executor pod logs
kubectl logs -n spark spark-worker-lab2-xxx --tail=50

# Verify Elastic Agent is reading logs (on host)
sudo tail -f /var/log/elastic-agent/elastic-agent.log | grep spark

# Check Elastic Agent process on host
ps aux | grep elastic-agent
```

#### **Elasticsearch Verification**
```bash
# Check if executor GC logs are being collected
curl -k -u "elastic:password" "https://garypc.lan:9200/logs-spark_gc-default/_search?size=5&sort=@timestamp:desc"

# Verify log source is from Kubernetes hosts
curl -k -u "elastic:password" "https://garypc.lan:9200/logs-spark_gc-default/_search" | jq '.hits.hits[]._source.host.name'
```

## Conclusion

The updated architecture implements **file-based logging best practices** for Spark applications while maintaining backward compatibility with container logging. The key insight is that **dedicated log files provide better separation and parsing efficiency** for complex applications like Spark, while still supporting container-based fallbacks.

### Key Benefits

1. **Improved Log Separation**: Application logs and GC logs are cleanly separated
2. **Better Performance**: Direct file parsing eliminates container log overhead
3. **Flexible Deployment**: Supports both development and production environments
4. **Maintainable Configuration**: Clear paths and simple Elastic Agent processors
5. **Backward Compatibility**: Existing container log configurations continue to work

This approach scales well for Spark workloads, provides clear observability boundaries, and maintains the flexibility needed for both development and production deployments while delivering comprehensive monitoring through the Elastic Stack.
