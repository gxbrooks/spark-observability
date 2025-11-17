# Docker File System Mappings

## Overview

This document maps file system paths across three contexts:
1. **DevOps User Context** (`~/repos/elastic-on-spark/observability/`): Development and source control
2. **Ansible Operations Context** (`/home/ansible/observability/`): Deployment target on managed hosts
3. **Docker Container Context**: Runtime paths inside containers

## Core Principles

1. **Source of Truth**: DevOps user's `~/repos/elastic-on-spark/observability/` is the source repository
2. **Deployment Flow**: Ansible playbooks copy files from DevOps repo to managed hosts (`/home/ansible/observability/`)
3. **Container Runtime**: Docker Compose mounts host directories into containers at service-specific paths
4. **Volume Management**: Docker named volumes (`certs:`, `esdata:`, `kibanadata:`) persist data across container restarts

## File System Layout

### DevOps User Context (Source Repository)

```
~/repos/elastic-on-spark/observability/
├── certs/                          # Certificate generation scripts and config
│   ├── init-certs.sh              # Certificate initialization script
│   ├── instances.yml               # Certificate instance definitions
│   └── ca/                         # CA certificates (generated)
├── docker-compose.yml              # Docker Compose service definitions
├── .env                           # Environment variables (generated from vars/variables.yaml)
├── elasticsearch/                 # Elasticsearch configuration and scripts
│   ├── bin/                       # API client scripts (esapi, kapi)
│   │   ├── elastic_api.py         # Unified API client
│   │   ├── esapi                  # Elasticsearch API wrapper
│   │   ├── kapi                   # Kibana API wrapper
│   │   └── init-index.sh          # Index initialization script
│   ├── config/                    # Elasticsearch configuration files
│   │   ├── batch-events/          # Batch event configurations
│   │   ├── batch-metrics/         # Batch metrics configurations
│   │   ├── batch-traces/          # Batch trace configurations
│   │   ├── docker-metrics/        # Docker metrics configurations
│   │   ├── otel-traces/           # OpenTelemetry trace configurations
│   │   ├── spark-gc/              # Spark GC configurations
│   │   ├── spark-logs/             # Spark log configurations
│   │   └── system-metrics/        # System metrics configurations
│   ├── outputs/                   # Script output files (generated)
│   ├── Dockerfile                 # Custom Elasticsearch image
│   └── requirements.txt           # Python dependencies
├── grafana/                       # Grafana configuration
│   ├── data/                      # Grafana data (persistent)
│   ├── provisioning/             # Auto-provisioned dashboards and datasources
│   ├── plugins/                   # Grafana plugins
│   └── grafana.ini                # Grafana configuration
├── logstash/                      # Logstash configuration
│   ├── config/                    # Logstash configuration files
│   └── pipeline/                  # Logstash pipeline definitions
└── docs/                          # Documentation
    └── Docker_File_System_Mappings.md  # This file
```

### Ansible Operations Context (Deployment Target)

```
/home/ansible/observability/
├── certs/                         # Copied from DevOps repo
├── docker-compose.yml             # Copied from DevOps repo
├── .env                           # Generated from vars/variables.yaml
├── elasticsearch/                 # Copied from DevOps repo
│   ├── bin/                       # Scripts (esapi, kapi, init-index.sh)
│   ├── config/                    # Configuration files
│   └── outputs/                   # Created by Ansible (owner: ansible)
├── grafana/                       # Copied from DevOps repo
│   ├── data/                      # Created by Docker (owner: 472:472)
│   ├── provisioning/              # Copied from DevOps repo
│   └── plugins/                   # Created by Ansible (owner: 472:472)
└── logstash/                      # Copied from DevOps repo
```

### Docker Container Contexts

#### init-certs Service

| Host Path (Ansible Ops) | Container Path | Purpose |
|-------------------------|----------------|---------|
| `certs:` (Docker volume) | `/usr/share/elasticsearch/config/certs` | Certificate storage (generated) |
| `./certs/` | `/usr/share/elasticsearch/certs` | Certificate scripts and config |
| `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | Host CA certificate access (Windows/WSL) |

**Notes**:
- `certs:` volume is created by Docker and persists certificates across restarts
- `./certs/` contains the `init-certs.sh` script and `instances.yml` configuration
- `/mnt/c/Volumes/certs/Elastic` is a Windows/WSL path for host-level certificate access

#### es01 Service (Elasticsearch)

| Host Path (Ansible Ops) | Container Path | Purpose |
|-------------------------|----------------|---------|
| `esdata:` (Docker volume) | `/usr/share/elasticsearch/data` | Elasticsearch data (persistent) |
| `certs:` (Docker volume) | `/usr/share/elasticsearch/config/certs:ro` | Certificates (read-only) |
| `./elasticsearch/` | `/usr/share/elasticsearch/elasticsearch` | Configuration and scripts |

**Notes**:
- `esdata:` volume persists Elasticsearch indices and data
- `certs:` volume is mounted read-only for security
- `./elasticsearch/` provides access to configuration files and API scripts

#### set-kibana-password Service

| Host Path (Ansible Ops) | Container Path | Purpose |
|-------------------------|----------------|---------|
| `./elasticsearch/` | `/usr/share/elasticsearch/elasticsearch` | API scripts (esapi) |
| `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | CA certificate access |

#### kibana Service

| Host Path (Ansible Ops) | Container Path | Purpose |
|-------------------------|----------------|---------|
| `kibanadata:` (Docker volume) | `/usr/share/kibana/data` | Kibana data (persistent) |
| `certs:` (Docker volume) | `/etc/ssl/private/elastic/certs` | Certificates for Kibana |
| `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | CA certificate access |

#### init-index Service

| Host Path (Ansible Ops) | Container Path | Purpose |
|-------------------------|----------------|---------|
| `./elasticsearch/` | `/usr/share/elasticsearch/elasticsearch` | Configuration and scripts |
| `certs:` (Docker volume) | `/usr/share/elasticsearch/config/certs:ro` | Certificates (read-only) |
| `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | CA certificate access |

**Environment Variables** (set in docker-compose.yml):
- `ES_DIR=/usr/share/elasticsearch/elasticsearch`
- `ES_CONFIG_DIR=/usr/share/elasticsearch/elasticsearch/config`
- `ES_OUTPUTS_DIR=/usr/share/elasticsearch/elasticsearch/outputs`
- `ES_BIN_DIR=/usr/share/elasticsearch/elasticsearch/bin`
- `ES_CA_CERT=/usr/share/elasticsearch/config/certs/ca/ca.crt`

#### grafana Service

| Host Path (Ansible Ops) | Container Path | Purpose |
|-------------------------|----------------|---------|
| `certs:` (Docker volume) | `/etc/ssl/private/elastic/certs` | Certificates |
| `./grafana/data/` | `/var/lib/grafana/data` | Grafana data (persistent) |
| `./grafana/provisioning/` | `/etc/grafana/provisioning` | Auto-provisioned configs |
| `./grafana/plugins/` | `/var/lib/grafana/plugins` | Grafana plugins |
| `./grafana/grafana.ini` | `/etc/grafana/grafana.ini` | Grafana configuration |
| `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | CA certificate access |

#### logstash01 Service

| Host Path (Ansible Ops) | Container Path | Purpose |
|-------------------------|----------------|---------|
| `./logstash/pipeline/` | `/usr/share/logstash/pipeline:ro` | Pipeline definitions (read-only) |
| `./logstash/config/logstash.yml` | `/usr/share/logstash/config/logstash.yml` | Logstash configuration |
| `./logstash/config/debug-logstash.yml` | `/usr/share/logstash/config/debug-logstash.yml` | Debug configuration |
| `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | CA certificate access |

## Path Resolution in Scripts

### init-index.sh

The `init-index.sh` script uses environment variables to resolve paths:

```bash
# Environment variables (set in docker-compose.yml)
ES_DIR=/usr/share/elasticsearch/elasticsearch
ES_CONFIG_DIR=/usr/share/elasticsearch/elasticsearch/config
ES_OUTPUTS_DIR=/usr/share/elasticsearch/elasticsearch/outputs
ES_BIN_DIR=/usr/share/elasticsearch/elasticsearch/bin
ES_CA_CERT=/usr/share/elasticsearch/config/certs/ca/ca.crt

# Script changes to ES_DIR for relative path resolution
cd "${ES_DIR}"

# Uses ES_CONFIG_DIR for configuration files
esapi PUT /_ilm/policy/batch-events ${ES_CONFIG_DIR}/batch-events/batch-events.ilm.json

# Uses ES_OUTPUTS_DIR for output files
> ${ES_OUTPUTS_DIR}/batch-events.ilm.out.json
```

### init-certs.sh

The `init-certs.sh` script uses hardcoded paths relative to the container's working directory:

```bash
# Script runs from /usr/share/elasticsearch (container working directory)
# Certificates are generated into the certs: volume at:
# /usr/share/elasticsearch/config/certs/

# Scripts and config are mounted at:
# /usr/share/elasticsearch/certs/
```

## Variable Mapping Contexts

### DevOps User Context

When running scripts locally as the DevOps user:

```bash
# From ~/repos/elastic-on-spark/observability/
export ES_DIR="${HOME}/repos/elastic-on-spark/observability/elasticsearch"
export ES_CONFIG_DIR="${ES_DIR}/config"
export ES_OUTPUTS_DIR="${ES_DIR}/outputs"
export ES_BIN_DIR="${ES_DIR}/bin"
export ES_CA_CERT="/etc/ssl/certs/elastic/ca.crt"  # Host CA cert path
```

### Ansible Operations Context

When running via Ansible playbooks on managed hosts:

```bash
# From /home/ansible/observability/
export ES_DIR="/home/ansible/observability/elasticsearch"
export ES_CONFIG_DIR="${ES_DIR}/config"
export ES_OUTPUTS_DIR="${ES_DIR}/outputs"
export ES_BIN_DIR="${ES_DIR}/bin"
export ES_CA_CERT="/etc/ssl/certs/elastic/ca.crt"  # Host CA cert path
```

### Docker Container Context

When running inside containers (via docker-compose.yml):

```bash
# Inside container
export ES_DIR="/usr/share/elasticsearch/elasticsearch"
export ES_CONFIG_DIR="/usr/share/elasticsearch/elasticsearch/config"
export ES_OUTPUTS_DIR="/usr/share/elasticsearch/elasticsearch/outputs"
export ES_BIN_DIR="/usr/share/elasticsearch/elasticsearch/bin"
export ES_CA_CERT="/usr/share/elasticsearch/config/certs/ca/ca.crt"  # From certs: volume
```

## Docker Volumes

### Named Volumes

| Volume Name | Purpose | Mounted In | Persistence |
|------------|---------|------------|-------------|
| `certs:` | Elasticsearch certificates | init-certs, es01, kibana, init-index, grafana | Persistent (Docker managed) |
| `esdata:` | Elasticsearch indices and data | es01 | Persistent (Docker managed) |
| `kibanadata:` | Kibana saved objects and settings | kibana | Persistent (Docker managed) |

### Volume Lifecycle

- **Creation**: Volumes are created automatically by Docker Compose on first run
- **Persistence**: Volumes persist across container restarts and removals
- **Cleanup**: Use `docker compose down -v` to remove volumes (⚠️ **destroys data**)

## Deployment Flow

### Step 1: Source Repository (DevOps User)

```
~/repos/elastic-on-spark/observability/
├── All configuration files
├── All scripts
└── .env (generated from vars/variables.yaml)
```

### Step 2: Ansible Deployment

Ansible playbook (`ansible/playbooks/observability/deploy.yml`) copies files:

```yaml
# From: ~/repos/elastic-on-spark/observability/
# To: /home/ansible/observability/
```

**Copied Directories**:
- `certs/` → `certs/`
- `elasticsearch/` → `elasticsearch/`
- `grafana/` → `grafana/` (excluding `plugins/`)
- `logstash/` → `logstash/`

**Created Directories**:
- `elasticsearch/outputs/` (owner: ansible:ansible, mode: 0775)
- `grafana/plugins/` (owner: 472:472, mode: 0755)

**Copied Files**:
- `docker-compose.yml` → `docker-compose.yml`
- `.env` → `.env`

### Step 3: Docker Compose Runtime

Docker Compose mounts host directories into containers:

```yaml
volumes:
  - ./elasticsearch:/usr/share/elasticsearch/elasticsearch
  - ./grafana/data:/var/lib/grafana/data
  - ./logstash/pipeline:/usr/share/logstash/pipeline:ro
```

## Best Practices

### For Development (DevOps User)

1. **Edit files in source repository**: Always edit files in `~/repos/elastic-on-spark/observability/`
2. **Regenerate .env**: Run `python3 vars/generate_env.py -f observability` after changing `vars/variables.yaml`
3. **Test locally**: Use Docker Compose from the source repository directory
4. **Commit changes**: Commit all changes to Git before deploying

### For Deployment (Ansible Operations)

1. **Use playbooks**: Always deploy using Ansible playbooks, never manually copy files
2. **Verify paths**: Ensure `/home/ansible/observability/` exists and has correct permissions
3. **Check ownership**: Verify `elasticsearch/outputs/` is owned by `ansible:ansible`
4. **Monitor volumes**: Check Docker volumes are created and accessible

### For Container Runtime

1. **Use environment variables**: Scripts should use `ES_*` environment variables, not hardcoded paths
2. **Respect volume mounts**: Write persistent data to Docker volumes, not bind mounts
3. **Handle permissions**: Ensure container user has appropriate permissions for mounted directories
4. **Validate paths**: Scripts should validate required paths exist before use

## Troubleshooting

### Path Not Found Errors

**Symptom**: Script fails with "No such file or directory"

**Check**:
1. Verify environment variables are set correctly
2. Check Docker volume mounts in `docker-compose.yml`
3. Verify Ansible deployment copied all required files
4. Check file permissions on mounted directories

### Permission Denied Errors

**Symptom**: Script fails with "Permission denied"

**Check**:
1. Verify container user has appropriate permissions
2. Check ownership of `elasticsearch/outputs/` directory
3. Verify Docker volume permissions
4. Check SELinux/AppArmor policies (if applicable)

### Variable Resolution Issues

**Symptom**: Script uses wrong paths or can't find files

**Check**:
1. Verify `ES_*` environment variables in `docker-compose.yml`
2. Check `.env` file is generated correctly from `vars/variables.yaml`
3. Verify context-specific variable values in `vars/variables.yaml`
4. Check script uses environment variables, not hardcoded paths

## Related Documentation

- **[Variable_Flow.md](../../docs/Variable_Flow.md)**: Variable definition and flow
- **[Log_Architecture.md](../../docs/Log_Architecture.md)**: Log file system organization
- **[Elastic_API_Client.md](elasticsearch/docs/Elastic_API_Client.md)**: API client usage

