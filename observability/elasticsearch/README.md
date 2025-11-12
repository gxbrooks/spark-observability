# Elasticsearch Configuration and Scripts

This directory contains all Elasticsearch configuration, initialization scripts, and documentation for the observability stack.

## Directory Structure

```
elasticsearch/
├── bin/                          # Executable scripts
│   ├── init-index.sh            # Main initialization script
│   ├── apply-ilm-policies.sh    # Apply downsampling ILM policies
│   ├── attach-policies-to-datastreams.sh  # Attach policies to data streams
│   ├── validate-downsampling.sh # Validate downsampling configuration
│   ├── esapi                    # Elasticsearch API client wrapper
│   ├── kapi                     # Kibana API client wrapper
│   ├── elastic_api.py           # Python Elasticsearch API client
│   ├── gen-painless-json.sh     # Generate Painless scripts
│   └── snippets.sh              # Useful API snippets
│
├── config/                       # Configuration data
│   ├── batch-events/            # Batch event tracking
│   ├── batch-metrics/           # Batch metrics
│   ├── batch-traces/            # Batch tracing
│   ├── docker-metrics/          # Docker container metrics (downsampling)
│   ├── kubernetes-metrics/      # Kubernetes metrics (future)
│   ├── otel-traces/             # OpenTelemetry traces
│   ├── spark-gc/                # Spark GC logs and downsampling
│   ├── spark-logs/              # Spark application logs and downsampling
│   └── system-metrics/          # System-wide metrics (downsampling)
│
├── docs/                         # Documentation
│   ├── README.md                # Downsampling implementation guide
│   ├── Elastic_API_Client.md    # API client usage
│   ├── INIT_INDEX_INTEGRATION.md    # init-index.sh integration
│   └── INTEGRATION_SUMMARY.md   # Integration overview
│
├── outputs/                      # Runtime outputs (logs, results)
├── Dockerfile                    # Container build file
└── requirements.txt              # Python dependencies
```

## Configuration Directories

Each configuration directory contains:
- **ILM policies** (`.ilm.json`) - Index lifecycle management
- **Index templates** (`.template.json`) - Index structure definitions
- **Ingest pipelines** (`.pipeline.json`) - Data processing pipelines
- **Data views** (`.dataview.json`) - Kibana data view definitions
- **Searches** (`.search.json`) - Saved Kibana searches
- **Watchers** (`.watcher.json`) - Alerting rules

### Downsampling Configuration

Several directories contain downsampling ILM policies:

- **spark-gc/**: `spark-gc-downsampled.ilm.json` - GC events downsampling
- **spark-logs/**: `spark-logs-metrics-downsampled.ilm.json` - Log metrics downsampling
- **system-metrics/**: `system-metrics.ilm.json` - System metrics downsampling
- **docker-metrics/**: `docker-metrics.ilm.json` - Docker metrics downsampling

## Scripts

### init-index.sh

Main initialization script that creates all Elasticsearch indices, ILM policies, templates, and Kibana data views.

**Location**: `bin/init-index.sh`

**Usage**:
```bash
cd bin
./init-index.sh
```

**What it does**:
- STEP 1-4: Wait for services and enable trial license
- STEP 5-9: Initialize batch events, metrics, and traces
- **STEP 10: Initialize downsampling ILM policies** (NEW)
- STEP 11-13: Initialize Spark GC, logs, and OTEL traces

### apply-ilm-policies.sh

Manually applies or updates downsampling ILM policies.

**Location**: `bin/apply-ilm-policies.sh`

**Usage**:
```bash
cd bin
./apply-ilm-policies.sh
```

### attach-policies-to-datastreams.sh

Attaches downsampling ILM policies to existing data streams.

**Location**: `bin/attach-policies-to-datastreams.sh`

**Usage**:
```bash
cd bin
./attach-policies-to-datastreams.sh
```

### validate-downsampling.sh

Validates downsampling configuration and monitors execution.

**Location**: `bin/validate-downsampling.sh`

**Usage**:
```bash
cd bin
./validate-downsampling.sh
```

## Quick Start

### Fresh Installation

```bash
# 1. Initialize everything (includes downsampling ILM policies)
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin
./init-index.sh

# 2. Attach policies to data streams
./attach-policies-to-datastreams.sh

# 3. Validate
./validate-downsampling.sh
```

### Updating ILM Policies

```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin
./apply-ilm-policies.sh
./attach-policies-to-datastreams.sh
```

## API Clients

### esapi

Elasticsearch API client wrapper that handles authentication and SSL.

**Usage**:
```bash
./esapi GET /_cat/indices
./esapi PUT /_ilm/policy/my-policy ../config/some-dir/policy.json
```

### kapi

Kibana API client wrapper.

**Usage**:
```bash
./kapi GET /api/status
./kapi POST /api/data_views/data_view ../config/some-dir/dataview.json
```

## Environment Variables

Required environment variables (set in docker-compose or shell):
- `ELASTIC_HOST` - Elasticsearch hostname
- `ELASTIC_PORT` - Elasticsearch port (default: 9200)
- `ELASTIC_USER` - Elasticsearch username (default: elastic)
- `ELASTIC_PASSWORD` - Elasticsearch password
- `KIBANA_HOST` - Kibana hostname
- `KIBANA_PORT` - Kibana port (default: 5601)
- `KIBANA_PASSWORD` - Kibana password
- `CA_CERT` - Path to CA certificate

## Retention Configuration

Downsampling retention periods are defined in `/variables.yaml`:

```yaml
ES_RETENTION_BASE:      2d   # Hot tier - original 30s data
ES_RETENTION_5MIN:      4d   # Warm tier - 5-minute downsampled
ES_RETENTION_15MIN:     8d   # Cold tier - 15-minute downsampled
ES_RETENTION_60MIN:     12d  # Frozen tier - 60-minute downsampled
```

## Adding New Metrics

To add a new metric type (e.g., kubernetes-metrics):

1. Create directory: `mkdir config/kubernetes-metrics`
2. Add ILM policy: `config/kubernetes-metrics/kubernetes-metrics.ilm.json`
3. Add to `init-index.sh` in a new step
4. Add to `apply-ilm-policies.sh`
5. Add to `attach-policies-to-datastreams.sh`
6. Document in `docs/`

## Documentation

- **Downsampling Implementation**: `docs/README.md`
- **API Client Usage**: `docs/Elastic_API_Client.md`
- **Integration Details**: `docs/INTEGRATION_SUMMARY.md`
- **Init-Index Integration**: `docs/INIT_INDEX_INTEGRATION.md`

## Outputs

The `outputs/` directory contains runtime outputs from init-index.sh:
- ILM policy creation responses
- Index template responses
- Data view creation responses

## Docker Support

The `Dockerfile` in this directory can be used to build a container with all necessary tools for Elasticsearch management.

## Contributing

When adding new configuration:
1. Place JSON files in appropriate `config/` subdirectory
2. Update `init-index.sh` to include new configuration
3. Add documentation to `docs/`
4. Keep scripts in `bin/`

## See Also

- Main observability README: `../README.md`
- Grafana dashboards: `../grafana/`
- Docker Compose: `../docker-compose.yml`
- Variables: `../../variables.yaml`

