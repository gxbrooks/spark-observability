# Elasticsearch Configuration and Initialization

This directory contains Elasticsearch and Kibana configuration, initialization scripts, and Index Lifecycle Management (ILM) policies for the observability platform.

## Purpose

Provides centralized management of:
- Elasticsearch indices, templates, and data streams
- ILM policies with automatic downsampling
- Kibana data views and saved searches
- Ingest pipelines for log processing
- Watcher-based event correlation

## Directory Organization

```
elasticsearch/
├── bin/              # Executable scripts and API clients
├── config/           # Configuration data (JSON files)
├── docs/             # Documentation
├── outputs/          # Runtime outputs (logs, API responses)
├── Dockerfile        # Container build file
└── requirements.txt  # Python dependencies
```

### bin/

Executable scripts for Elasticsearch and Kibana initialization and management.

**Main Scripts**:
- `init-index.sh` - Complete initialization (indices, templates, ILM policies, data views)
- `esapi` - Elasticsearch API client wrapper
- `kapi` - Kibana API client wrapper
- `validate-downsampling.sh` - Validate ILM downsampling configuration

**Usage**: Add to PATH:
```bash
export PATH="${PATH}:/home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin"
```

See `bin/README.md` for detailed script documentation.

### config/

Configuration data organized by functionality:

- `batch-events/` - Spark batch job event tracking (watchers, templates)
- `batch-metrics/` - Batch job metrics aggregation
- `batch-traces/` - Distributed tracing for batch jobs
- `docker-metrics/` - Docker container metrics with downsampling
- `kubernetes-metrics/` - Kubernetes metrics (future)
- `otel-traces/` - OpenTelemetry distributed tracing
- `spark-gc/` - Spark GC logs and downsampling policies
- `spark-logs/` - Spark application logs, transforms, and downsampling
- `system-metrics/` - System-wide metrics with downsampling

Each directory contains JSON files: templates (`.template.json`), ILM policies (`.ilm.json`), data views (`.dataview.json`), etc.

### docs/

Documentation files:
- `Elastic_API_Client.md` - esapi/kapi usage and exit code patterns
- `Lifecycle_Policies.md` - ILM policies and downsampling configuration

## Architecture

### Initialization Flow

```
init-index.sh
  ├─> STEP 1-4: Service health checks, trial license
  ├─> STEP 5-9: Batch events, traces, metrics
  ├─> STEP 10: Downsampling ILM policies + attachment
  ├─> STEP 11-12: Spark GC, logs, transforms
  └─> STEP 13: OpenTelemetry traces
```

### Data Flow

```
Spark/System → Elastic Agent → Ingest Pipelines → Data Streams
                                                         ↓
                                                    ILM Policies
                                                         ↓
                                    Hot → Warm → Cold → Delete
                                   (30s → 5m → 15m → 60m)
```

## Prerequisites

### Environment Variables

Required in docker-compose or shell environment:

**Elasticsearch**:
- `ELASTIC_HOST` - Hostname (e.g., es01, GaryPC.local)
- `ELASTIC_PORT` - Port (default: 9200)
- `ELASTIC_USER` - Username (default: elastic)
- `ELASTIC_PASSWORD` - Password
- `CA_CERT` - Path to CA certificate

**Kibana**:
- `KIBANA_HOST` - Hostname
- `KIBANA_PORT` - Port (default: 5601)
- `KIBANA_PASSWORD` - Password

### Python Dependencies

- Python 3.x
- `requests` module (installed via `linux/assert_devops_client.sh`)

## Main Entrypoint

### init-index.sh

Initializes complete Elasticsearch and Kibana configuration from source.

**Usage**:
```bash
cd bin
./init-index.sh
```

**What it does**:
1. Waits for Elasticsearch and Kibana availability
2. Enables trial license (for watchers)
3. Creates all ILM policies (including downsampling)
4. Creates index templates
5. Creates ingest pipelines
6. Creates data views in Kibana
7. Creates saved searches
8. Attaches ILM policies to existing data streams
9. Creates and starts transforms

**Output**: Results written to `outputs/` directory

**Container Mode**: Runs automatically in Docker Compose as `init-index` service

## Downsampling

Automatic progressive downsampling for long-term metric retention:

- **30-second** data retained for **2 days** (hot tier)
- **5-minute** downsampled data for **days 2-4** (hot tier)
- **15-minute** downsampled data for **days 4-8** (warm tier)
- **60-minute** downsampled data for **days 8-12** (cold tier)
- Data **deleted** after **12 days**

**Configuration**: See `docs/Lifecycle_Policies.md`

**Retention Settings**: `/vars/variables.yaml` (lines 36-53)

**Important**: Current retention periods are for **test/lab purposes**. Adjust for enterprise deployments.

## Adding New Metrics

To add a new metric type (e.g., kubernetes-metrics):

1. Create configuration directory:
   ```bash
   mkdir config/kubernetes-metrics
   ```

2. Add ILM policy:
   ```bash
   vi config/kubernetes-metrics/kubernetes-metrics.ilm.json
   ```

3. Update `bin/init-index.sh` - add new step or integrate into STEP 10:
   ```bash
   echo "Creating kubernetes-metrics ILM policy..."
   esapi PUT /_ilm/policy/kubernetes-metrics ${CONFIG_DIR}/kubernetes-metrics/kubernetes-metrics.ilm.json \
     > ${OUTPUTS_DIR}/kubernetes-metrics.ilm.out.json
   ```

4. Attach policy to data stream in same step:
   ```bash
   if esapi --allow-errors GET "/_data_stream/metrics-kubernetes-default" > /dev/null 2>&1; then
     esapi PUT "metrics-kubernetes-default/_settings" -d '{"index.lifecycle.name":"kubernetes-metrics"}' > /dev/null 2>&1 || true
   fi
   ```

## API Clients

### esapi - Elasticsearch API

```bash
esapi GET /_cluster/health
esapi PUT /_ilm/policy/my-policy config/my-policy.ilm.json
```

### kapi - Kibana API

```bash
kapi GET /api/status
kapi POST /api/data_views/data_view config/my-dataview.json
```

See `docs/Elastic_API_Client.md` for detailed usage and exit codes.

## Deployment

### Via Ansible

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/observability/deploy.yml
ansible-playbook -i inventory.yml playbooks/observability/start.yml
```

Ansible deploys configuration and starts services, which runs `init-index.sh` automatically.

### Manual

```bash
cd observability
docker-compose up -d
```

The `init-index` container runs automatically as part of the service dependency chain.

## Verification

### Check ILM Policies

```bash
esapi GET /_ilm/policy/*downsampled
```

### Check Policy Attachment

```bash
esapi GET /metrics-system.cpu-default/_ilm/explain
```

### Validate Configuration

```bash
cd bin
./validate-downsampling.sh
```

## Related Documentation

- **Lifecycle Policies**: `docs/Lifecycle_Policies.md` - ILM policy details and retention
- **API Clients**: `docs/Elastic_API_Client.md` - esapi/kapi usage patterns
- **Scripts**: `bin/README.md` - Detailed script documentation
- **Implementation**: `/observability/DOWNSAMPLING_IMPLEMENTATION.md` - Full implementation details
- **Quick Start**: `/observability/QUICK_START_DOWNSAMPLING.md` - Deployment guide

## Key Design Principles

### Build from Source
All configuration is version-controlled and deployed from JSON files via `init-index.sh`.

### Co-location
Related configuration files reside together (e.g., downsampling policies with their base metrics).

### Idempotency
Scripts can be run multiple times safely. Existing resources are detected and skipped.

### Automation
ILM policies automatically downsample data as it ages. No manual intervention required.
