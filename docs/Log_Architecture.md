# Log Architecture for Spark-on-Kubernetes Observability

## Overview

This document outlines the comprehensive logging architecture for Spark applications running on Kubernetes, with Elastic Agent collecting and processing logs for observability. The architecture implements host-based logging with proper user management and file system organization.

## Core Principles

1. **NFS-Based Event Storage**: Spark event logs stored on NFS server (**Lab3** in the target layout) for centralized access
2. **Proper User Management**: Elastic Agent runs as dedicated `elastic-agent` user with appropriate group memberships
3. **Centralized Event Storage**: Spark event logs stored in `/mnt/spark/events` accessible by History Server and Elastic Agent
4. **File-Based Collection**: Direct file access for better parsing and separation of log types
5. **Rich Metadata**: Comprehensive tagging for filtering and analysis in Kibana

## Deployment Architecture

### Physical Infrastructure

```
┌─────────────────────────┐    ┌─────────────────────────────────────────┐
│ Local Development       │    │ Kubernetes hosts (Lab1–Lab3; see topology) │
│ Machine (gxbrooks)      │    │                                         │
│                         │    │ ┌─────────────────────────────────────┐ │
│ ├── Python Process      │    │ │ Host OS (Ubuntu/Linux)              │ │
│ │   └── Chapter_04.py   │    │ │                                     │ │
│ ├── Driver JVM          │    │ │ ├── elastic-agent (user: 997)      │ │
│ │   └── Console logs    │    │ │ │   ├── Group: elastic-agent (984)  │ │
│ │       (not monitored) │    │ │ │   ├── Group: spark (185)          │ │
│ │                       │    │ │ │   └── Monitors host files        │ │
│ └── No Elastic Agent    │    │ │                                     │ │
└─────────────────────────┘    │ │ ├── Kubernetes Runtime             │ │
                               │ │ │   ├── kubelet                    │ │
                               │ │ │   ├── Container runtime          │ │
                               │ │ │   └── Pod logs → /var/log/pods/  │ │
                               │ │ │                                   │ │
                               │ │ └── Kubernetes Pods                │ │
                               │ │     ├── Spark Master Pod           │ │
                               │ │     ├── Spark Worker Pods          │ │
                               │ │     │   └── Executor JVMs           │ │
                               │ │     │       ├── GC logs → files    │ │
                               │ │     │       └── App logs → files   │ │
                               │ │     └── History Server Pod         │ │
                               │ │         └── Event logs → /opt/spark/events │
                               │ └─────────────────────────────────────┐ │
                               └─────────────────────────────────────────┘
```

### File System Layout

```
NFS Server (Lab3)                Host Machines (Lab1, Lab2, Lab3)
├── /mnt/spark/events/           ├── /mnt/spark/logs/             # Application and GC logs
│   ├── app-20251026122735-0063  │   ├── spark_spark-master-0_uid/
│   ├── app-20251026122754-0064  │   │   ├── master-gc.log
│   └── app-20251026122823-0065  │   │   └── master-app.log
│                                │   ├── spark_spark-worker-*_uid/
│                                │   │   ├── worker-gc.log
│                                │   │   └── worker-app.log
│                                │   └── executor-gc-*.log        # Executor GC logs
│                                └── /var/log/pods/               # Kubernetes container logs
│                                    └── spark_*/                 # Pod-specific directories
```

## Log Flow Architecture

### Client Mode (Development)

When running Spark applications locally that connect to a remote Kubernetes cluster:

```
Local Machine (Driver)                    Kubernetes Cluster (Executors)           NFS Server (Lab3)
├── Driver JVM (PySpark 4.0.1)          ├── Executor JVMs (in pods)               ├── /mnt/spark/events/
│   ├── GC logs → console               │   ├── GC logs → /mnt/spark/logs/        │   └── Event logs
│   └── Event logs → /mnt/spark/events/ │   ├── App logs → /mnt/spark/logs/        │
│        (via NFS mount)                │   └── Event logs → /mnt/spark/events/    │
└── No Elastic Agent needed              │        (via NFS mount)                  │
                                         └── Elastic Agent (NFS server, Lab3) → Logstash → Elasticsearch
```

**Data Flow**: Spark Driver → NFS → Elastic Agent → Logstash → Elasticsearch

**Key Insight**: In client mode, **only executor logs matter for observability**. Driver logs are local development artifacts and should not be part of production monitoring.

### Cluster Mode (Production)

When running Spark applications entirely within Kubernetes:

```
Kubernetes Cluster (Both Driver & Executors)    NFS Server (Lab3)
├── Driver JVM (in pod) → stdout → /var/log/pods/  ├── /mnt/spark/events/
├── Executor JVMs (in pods) → stdout → /var/log/pods/  └── Event logs
├── Event logs → /mnt/spark/events/ (via NFS mount)
└── Elastic Agent (NFS server, Lab3) → Logstash → Elasticsearch
```

**Data Flow**: Spark Applications → NFS → Elastic Agent → Logstash → Elasticsearch

## User and Group Management

### Service Account Architecture

**Elastic Agent User**:
- **UID**: 997 (system account)
- **GID**: 984 (elastic-agent group)
- **Additional Groups**: spark (185) - for reading Spark logs
- **Home Directory**: `/opt/Elastic/Agent`
- **Shell**: `/usr/sbin/nologin` (service account)
- **Deployment**: On the **NFS server host (Lab3)** for centralized event log processing

**Spark User**:
- **UID/GID**: 185 (matches Kubernetes pod security context)
- **Purpose**: Owns Spark application files and logs
- **Group Members**: elastic-agent, gxbrooks, ansible

### Group Membership Matrix

| User | Primary Group | Secondary Groups | Purpose |
|------|--------------|------------------|---------|
| **elastic-agent** | elastic-agent (984) | spark (185) | Monitor Spark logs |
| **spark** | spark (185) | *(none)* | Own Spark files |
| **gxbrooks** | gxbrooks (1000) | spark (185), elastic-agent (984) | Administration |
| **ansible** | ansible (1001) | elastic-agent (984) | Service management |

## Log Collection Strategy

### Elastic Agent Configuration

**Host-Based Deployment**:
- Runs as host process on Kubernetes nodes (Lab1, Lab2, Lab3 as deployed)
- Direct filesystem access to mounted log directories
- Collects from multiple sources:
  - System metrics (CPU, memory, network, disk)
  - System logs (auth.log, syslog)
  - Kubernetes metrics (container, pod, node)
  - Spark application logs (`/mnt/spark/logs/*/`)
- **Event Log Processing**: On the **NFS server host (Lab3)** (mounted `/mnt/spark/events`)
  - Spark event logs (`/mnt/spark/events/app-*`)

**Log Processing**:
- **GC Logs**: Java 11 unified format with single dissect pattern
- **Application Logs**: Separate processing pipeline
- **Event Logs**: JSON format with structured metadata
- **Metadata Enrichment**: Pod information, host details, deployment type

### Data Flow

```
Spark Components                                    Host Machines (Lab1, Lab2, Lab3) NFS Server (Lab3)
├── Master/Worker Pods                             ├── /mnt/spark/logs/               ├── /mnt/spark/events/
│   ├── GC logs → files                           │   ├── spark_spark-master-0_uid/   │   ├── app-20251026122735-0063
│   └── App logs → files                          │   │   ├── master-gc.log           │   ├── app-20251026122754-0064
├── History Server Pod                             │   │   └── master-app.log          │   └── app-20251026122823-0065
│   └── Event logs → /mnt/spark/events            │   ├── spark_spark-worker-*_uid/   │
└── Executor Pods                                  │   │   ├── worker-gc.log           │
    └── Event logs → /mnt/spark/events            │   │   └── worker-app.log          │
                                                    │   └── executor-gc-*.log          │

Host Machines (Lab1, Lab2, Lab3)                    NFS Server (Lab3)                 Elasticsearch
├── Elastic Agent (elastic-agent user)             ├── Elastic Agent (event logs, Lab3) ├── Index: logs-spark_gc-default
│   ├── Reads mounted files                       │   ├── Reads event logs            ├── Index: logs-spark-default
│   ├── Processes with dissect                    │   ├── Processes JSON events       ├── Index: logs-spark-spark-default
│   ├── Extracts metrics                          │   └── Ships to Elasticsearch      └── Rich metadata and timestamps
│   └── Ships to Elasticsearch
```

## Event Log Architecture

### Centralized Event Storage

**Path**: `/mnt/spark/events/`
**Purpose**: Centralized NFS location for all Spark event logs accessible by History Server and Elastic Agent
**Access**: 
- History Server pod mounts this NFS directory
- Elastic Agent on the NFS server host (Lab3) monitors this directory
- All Spark applications write events here via NFS mount

**Benefits**:
- **History Server Access**: Can read all event logs regardless of which host they were created on
- **Elastic Agent Monitoring**: Single location for event log collection on the **NFS server (Lab3)**
- **NFS Centralization**: All event logs stored on NFS server for centralized access
- **Consistent Paths**: All components use same event log directory

### Event Log Flow

```
Spark Applications (Client Mode)                    NFS Server (Lab3)
├── Local Driver → submits to cluster              ├── /mnt/spark/events/
├── Remote Executors → write events to /mnt/spark/events/  └── Event logs
└── History Server → reads from /mnt/spark/events/

Elastic Agent (NFS server, Lab3)                    Logstash
├── Monitors /mnt/spark/events/app-*               ├── Receives events from Elastic Agent
├── Processes JSON event logs                      ├── Creates batch events
└── Forwards to Logstash                           └── Sends to Elasticsearch
```

## Observability Benefits

### Performance Metrics
- **GC Pause Times**: Track impact on job execution
- **Heap Utilization**: Monitor memory pressure
- **Collection Frequency**: Identify excessive GC activity
- **Transmission Latency**: Measure log pipeline performance

### Alerting Capabilities
- High pause times (> 100ms)
- Frequent full GC collections
- Memory pressure indicators
- Log transmission delays
- Missing event logs

### Rich Metadata
- **Host Information**: Physical host identifier
- **Pod Details**: Kubernetes pod name and namespace
- **Spark Role**: Normalized component role (master, worker, executor)
- **Deployment Type**: Kubernetes vs Docker Compose
- **Timestamp Management**: Dual timestamps for latency measurement

## Future Enhancements

### Spark Listeners Integration
- **Direct Logstash Integration**: Spark listeners send events directly to Logstash
- **Real-time Processing**: Eliminate file-based collection for event logs
- **Reduced Latency**: Direct network transmission instead of file I/O
- **Simplified Architecture**: Remove file monitoring for event logs

### Implementation Strategy
1. **Custom Spark Listener**: Implement listener to capture Spark events
2. **Logstash HTTP Input**: Configure Logstash to receive events via HTTP
3. **Event Transformation**: Process events in real-time
4. **Backward Compatibility**: Maintain file-based collection as fallback

## Best Practices

### For Spark Applications
1. **Understand deployment mode**: Client mode (driver local) vs Cluster mode (driver in K8s)
2. **Focus observability on executors**: Only executor logs matter for production monitoring
3. **Configure proper logging**: Use file-based logging for production observability
4. **Minimize driver logging**: Basic GC only for client mode development
5. **Centralize event logs**: Use `/mnt/spark/events` for all event log storage

### For Elastic Agent
1. **Use dedicated service account**: Run as `elastic-agent` user with proper group memberships
2. **Monitor host-mounted directories**: Direct filesystem access for better performance
3. **Separate log types**: Different processing pipelines for GC, app, and event logs
4. **Set appropriate permissions**: Ensure elastic-agent user can read Spark log files
5. **Use data streams**: Separate indices for different log types

### For System Administration
1. **Maintain user consistency**: Ensure elastic-agent user exists on all hosts
2. **Verify group memberships**: elastic-agent must be in spark group
3. **Monitor disk usage**: Event logs can grow large over time
4. **Regular cleanup**: Implement log rotation and retention policies
5. **Test log collection**: Verify Elastic Agent can read all log files

## Conclusion

This architecture provides comprehensive observability for Spark-on-Kubernetes deployments through:

1. **Proper User Management**: Dedicated elastic-agent service account with appropriate permissions
2. **Centralized Event Storage**: Single NFS location for all Spark event logs accessible by History Server and Elastic Agent
3. **Host-Based Collection**: Direct filesystem access for optimal performance
4. **Rich Metadata**: Comprehensive tagging for filtering and analysis
5. **Future-Ready**: Architecture supports direct Logstash integration via Spark listeners

The system is production-ready and provides the foundation for advanced observability features while maintaining simplicity and reliability.

---

## Related Documentation

- **[Lab_Topology_and_Resources.md](Lab_Topology_and_Resources.md)** — Which lab runs NFS, Kubernetes, and observability.

For comprehensive details on Elastic Agent configuration and telemetry collection:
- **[Elastic Agent Architecture](../elastic-agent/docs/Elastic_Agent_Architecture.md)** - Complete telemetry collection architecture, including:
  - System metrics collection strategy
  - Kubernetes metrics (planned)
  - Spark log collection (application logs & GC logs)
  - Spark event collection and duplicate prevention
  - Configuration management with templates and host variables
  - Deployment procedures and troubleshooting

This document (Log_Architecture.md) focuses on the overall logging strategy and file system organization, while the Elastic Agent Architecture document provides implementation details for the collection layer.