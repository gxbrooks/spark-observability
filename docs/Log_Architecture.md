# Log Architecture for Spark-on-Kubernetes Observability

## Overview

This document outlines the comprehensive logging architecture for Spark applications running on Kubernetes, with Elastic Agent collecting and processing logs for observability. The architecture implements host-based logging with proper user management and file system organization.

## Core Principles

1. **Host-Based Logging**: All Spark components write logs to host-mounted directories for direct access by Elastic Agent
2. **Proper User Management**: Elastic Agent runs as dedicated `elastic-agent` user with appropriate group memberships
3. **Centralized Event Storage**: Spark event logs stored in `/opt/spark/events` accessible by History Server
4. **File-Based Collection**: Direct file access for better parsing and separation of log types
5. **Rich Metadata**: Comprehensive tagging for filtering and analysis in Kibana

## Deployment Architecture

### Physical Infrastructure

```
┌─────────────────────────┐    ┌─────────────────────────────────────────┐
│ Local Development       │    │ Kubernetes Host Machines (Lab1, Lab2)   │
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
Host Machine (Lab1, Lab2)
├── /opt/spark/events/           # Spark event logs (History Server access)
│   ├── app-20251026122735-0063
│   ├── app-20251026122754-0064
│   └── app-20251026122823-0065
├── /mnt/spark/logs/             # Application and GC logs
│   ├── spark_spark-master-0_uid/
│   │   ├── master-gc.log
│   │   └── master-app.log
│   ├── spark_spark-worker-*_uid/
│   │   ├── worker-gc.log
│   │   └── worker-app.log
│   └── executor-gc-*.log        # Executor GC logs
└── /var/log/pods/               # Kubernetes container logs
    └── spark_*/                 # Pod-specific directories
```

## Log Flow Architecture

### Client Mode (Development)

When running Spark applications locally that connect to a remote Kubernetes cluster:

```
Local Machine (Driver)                    Kubernetes Cluster (Executors)
├── Driver JVM                           ├── Executor JVMs (in pods)
│   ├── GC logs → console               │   ├── GC logs → /mnt/spark/logs/
│   └── (Not monitored)                  │   ├── App logs → /mnt/spark/logs/
│                                        │   └── Event logs → /opt/spark/events/
└── No Elastic Agent needed              │
                                         └── Elastic Agent (on K8s hosts) → Elasticsearch
```

**Key Insight**: In client mode, **only executor logs matter for observability**. Driver logs are local development artifacts and should not be part of production monitoring.

### Cluster Mode (Production)

When running Spark applications entirely within Kubernetes:

```
Kubernetes Cluster (Both Driver & Executors)
├── Driver JVM (in pod) → stdout → /var/log/pods/
├── Executor JVMs (in pods) → stdout → /var/log/pods/
├── Event logs → /opt/spark/events/ (History Server)
└── Elastic Agent (on K8s hosts) → Elasticsearch
```

## User and Group Management

### Service Account Architecture

**Elastic Agent User**:
- **UID**: 997 (system account)
- **GID**: 984 (elastic-agent group)
- **Additional Groups**: spark (185) - for reading Spark logs
- **Home Directory**: `/opt/Elastic/Agent`
- **Shell**: `/usr/sbin/nologin` (service account)

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
- Runs as host process on Kubernetes nodes (Lab1, Lab2)
- Direct filesystem access to mounted log directories
- Collects from multiple sources:
  - System metrics (CPU, memory, network, disk)
  - System logs (auth.log, syslog)
  - Kubernetes metrics (container, pod, node)
  - Spark application logs (`/mnt/spark/logs/*/`)
  - Spark event logs (`/opt/spark/events/app-*`)

**Log Processing**:
- **GC Logs**: Java 11 unified format with single dissect pattern
- **Application Logs**: Separate processing pipeline
- **Event Logs**: JSON format with structured metadata
- **Metadata Enrichment**: Pod information, host details, deployment type

### Data Flow

```
Spark Components                                    Host Machine
├── Master/Worker Pods                             ├── /mnt/spark/logs/
│   ├── GC logs → files                           │   ├── spark_spark-master-0_uid/
│   └── App logs → files                          │   │   ├── master-gc.log
├── History Server Pod                             │   │   └── master-app.log
│   └── Event logs → /opt/spark/events            │   ├── spark_spark-worker-*_uid/
└── Executor Pods                                  │   │   ├── worker-gc.log
    └── Event logs → /opt/spark/events            │   │   └── worker-app.log
                                                    │   └── executor-gc-*.log
                                                    └── /opt/spark/events/
                                                        ├── app-20251026122735-0063
                                                        ├── app-20251026122754-0064
                                                        └── app-20251026122823-0065

Host Machine                                       Elasticsearch
├── Elastic Agent (elastic-agent user)             ├── Index: logs-spark_gc-default
│   ├── Reads mounted files                       ├── Index: logs-spark-default
│   ├── Processes with dissect                    ├── Index: logs-spark-spark-default
│   ├── Extracts metrics                          └── Rich metadata and timestamps
│   └── Ships to Elasticsearch
```

## Event Log Architecture

### Centralized Event Storage

**Path**: `/opt/spark/events/`
**Purpose**: Centralized location for all Spark event logs accessible by History Server
**Access**: 
- History Server pod mounts this directory
- Elastic Agent monitors this directory
- All Spark applications write events here

**Benefits**:
- **History Server Access**: Can read all event logs regardless of which host they were created on
- **Elastic Agent Monitoring**: Single location for event log collection
- **No NFS Dependencies**: Uses host mounts instead of network file system
- **Consistent Paths**: All components use same event log directory

### Event Log Flow

```
Spark Applications (Client Mode)
├── Local Driver → submits to cluster
├── Remote Executors → write events to /opt/spark/events/
└── History Server → reads from /opt/spark/events/

Elastic Agent
├── Monitors /opt/spark/events/app-*
├── Processes JSON event logs
└── Forwards to Elasticsearch
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
5. **Centralize event logs**: Use `/opt/spark/events` for all event log storage

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
2. **Centralized Event Storage**: Single location for all Spark event logs accessible by History Server
3. **Host-Based Collection**: Direct filesystem access for optimal performance
4. **Rich Metadata**: Comprehensive tagging for filtering and analysis
5. **Future-Ready**: Architecture supports direct Logstash integration via Spark listeners

The system is production-ready and provides the foundation for advanced observability features while maintaining simplicity and reliability.