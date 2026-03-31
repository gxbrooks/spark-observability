# File System Architecture

## Overview

This document describes the file system architecture for the spark-observability project, covering all file system types, host environments, and the mappings between them. **Primary targets are native Linux lab hosts (Lab1–Lab3).** The observability Docker stack runs on **Lab3** under `/home/ansible/ops/observability`. **Target topology** (which host runs Kubernetes control plane, NFS, HDFS, Jupyter) is summarized in **[Lab_Topology_and_Resources.md](Lab_Topology_and_Resources.md)**. WSL/Windows paths below are **legacy** references only.

## Summary

The file system architecture uses a layered approach:

- **DevOps Environment**: Source repository on development machines (`~/repos/spark-observability/`)
- **Ops Environment**: Deployed files on managed hosts (`~/ansible/ops/`)
- **Docker File Systems**: Container runtime paths with volume mounts
- **Kubernetes File Systems**: Pod filesystems for Spark and OpenTelemetry

**Distribution Strategy**:
- **Application Binaries (JARs, executables)**: Ansible distribution to local filesystem
- **Runtime Data (logs, events, datasets)**: NFS for shared access
- **Configuration Files**: Ansible with Jinja2 templates
- **Docker Images**: Local registry

**Key Principle**: Match distribution mechanism to access pattern
- **Static, versioned, infrequent access**: Ansible
- **Dynamic, continuous, shared access**: NFS
- **Container images**: Registry

---

## File System Types

### 1. DevOps Environment

**Location**: `~/repos/spark-observability/` on development machines

**Purpose**: Source repository for all project files, version controlled in Git

**Structure**: `~/repos/spark-observability/` containing `ansible/` (Ansible playbooks and roles), `docs/` (documentation), `elastic-agent/` (Elastic Agent configurations and scripts), `observability/` (observability stack), `spark/` (Spark applications and configurations), `vars/` (variable definitions and generators), and other project directories.

**Characteristics**:
- Source of truth for all configuration and code
- Version controlled via Git
- Files are pushed to managed hosts via Ansible
- Not directly accessed by production services

### 2. Ops Environment

**Location**: `~/ansible/ops/` on managed hosts (native Linux; e.g. Lab3 for observability)

**Purpose**: Deployment target for files pushed from DevOps environment

**Structure**: `~/ansible/ops/` containing `observability/` (observability stack deployment with `certs/`, `docker-compose.yml`, `.env`, `elasticsearch/`, `grafana/`, `logstash/` subdirectories) and other deployed services.

**Mapping from DevOps**:
- `~/repos/spark-observability/observability/` → `~/ansible/ops/observability/`
- Deployed via Ansible playbooks (`ansible/playbooks/observability/deploy.yml`)

**Characteristics**:
- Files copied from DevOps environment via Ansible
- Used as mount points for Docker containers
- Contains runtime configuration files
- Not version controlled (managed via Ansible)

### 3. Docker File Systems

**Location**: Inside Docker containers, mounted from Ops environment  
**Purpose**: Runtime paths for containerized services (Elasticsearch, Kibana, Grafana, Logstash)

#### init-certs Service

| Host Path (Ops) | Container Path | Purpose |
|----------------|----------------|---------|
| `certs:` | `/usr/share/elasticsearch/config/certs` | Certificate storage (generated) |
| `./certs/` | `/usr/share/elasticsearch/certs` | Certificate scripts and config |
| `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | Host CA certificate access |

#### es01 Service (Elasticsearch)

| Host Path (Ops) | Container Path | Purpose |
|----------------|----------------|---------|
| `esdata:` | `/usr/share/elasticsearch/data` | Elasticsearch data (persistent) |
| `certs:` | `/usr/share/elasticsearch/config/certs:ro` | Certificates (read-only) |
| `./elasticsearch/` | `/usr/share/elasticsearch/elasticsearch` | Configuration and scripts |

#### kibana Service

| Host Path (Ops) | Container Path | Purpose |
|----------------|----------------|---------|
| `kibanadata:` | `/usr/share/kibana/data` | Kibana data (persistent) |
| `certs:` | `/etc/ssl/private/elastic/certs` | Certificates |
| `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | CA certificate access |

#### init-index Service

| Host Path (Ops) | Container Path | Purpose |
|----------------|----------------|---------|
| `./elasticsearch/` | `/usr/share/elasticsearch/elasticsearch` | Configuration and scripts |
| `certs:` | `/usr/share/elasticsearch/config/certs:ro` | Certificates (read-only) |
| `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | CA certificate access |

#### grafana Service

| Host Path (Ops) | Container Path | Purpose |
|----------------|----------------|---------|
| `certs:` | `/etc/ssl/private/elastic/certs` | Certificates |
| `./grafana/data/` | `/var/lib/grafana/data` | Grafana data (persistent) |
| `./grafana/provisioning/` | `/etc/grafana/provisioning` | Auto-provisioned configs |
| `./grafana/plugins/` | `/var/lib/grafana/plugins` | Grafana plugins |
| `./grafana/grafana.ini` | `/etc/grafana/grafana.ini` | Grafana configuration |
| `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | CA certificate access |

#### logstash01 Service

| Host Path (Ops) | Container Path | Purpose |
|----------------|----------------|---------|
| `./logstash/pipeline/` | `/usr/share/logstash/pipeline:ro` | Pipeline definitions (read-only) |
| `./logstash/config/logstash.yml` | `/usr/share/logstash/config/logstash.yml` | Logstash configuration |
| `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | CA certificate access |

#### Docker Volumes

| Volume Name | Purpose | Mounted In | Persistence |
|------------|---------|------------|-------------|
| `certs:` | Elasticsearch certificates | init-certs, es01, kibana, init-index, grafana | Persistent (Docker managed) |
| `esdata:` | Elasticsearch indices and data | es01 | Persistent (Docker managed) |
| `kibanadata:` | Kibana saved objects and settings | kibana | Persistent (Docker managed) |

**Environment Variables** (set in docker-compose.yml for init-index): `ES_DIR=/usr/share/elasticsearch/elasticsearch`, `ES_CONFIG_DIR=/usr/share/elasticsearch/elasticsearch/config`, `ES_OUTPUTS_DIR=/usr/share/elasticsearch/elasticsearch/outputs`, `ES_BIN_DIR=/usr/share/elasticsearch/elasticsearch/bin`, `CA_CERT=/usr/share/elasticsearch/config/certs/ca/ca.crt`

### 4. Kubernetes File Systems

**Location**: Inside Kubernetes pods for Spark and OpenTelemetry

**Purpose**: Runtime filesystems for Spark applications and OpenTelemetry collectors

#### Spark Pod Filesystems

**System-wide Spark Installation** (container): `/opt/spark/` with `bin/`, `jars/`, `python/`, `conf/`, `apps/` subdirectories.

**User-specific Configuration Directory** (host-mounted): `/home/ansible/spark/` with `conf/` and `k8s/` subdirectories containing Kubernetes manifests.

#### OpenTelemetry Pod Filesystems

OpenTelemetry collectors run in Kubernetes pods with configuration mounted from ConfigMaps or host paths.

#### NFS Mounts in Kubernetes

**Shared Storage**: NFS server at `/srv/nfs/spark` on the **NFS server host (target: Lab3)** mounted at `/mnt/spark` on all Kubernetes nodes (Lab1–Lab3). Subdirectories: `/mnt/spark/events` (Spark event logs, shared read/write), `/mnt/spark/data` (shared datasets, shared read), `/mnt/spark/checkpoints` (streaming checkpoints, shared read/write), `/mnt/spark/logs` (application and GC logs, per-host, symlinked to kubelet logs).

---

## Host Type Variations

### Native Linux Hosts

**Examples**: Lab1, Lab2, Lab3 (Ubuntu/Linux). **Lab1 and Lab2** are symmetric Spark/Kubernetes **workers**. **Lab3** runs the observability stack, **Kubernetes control plane**, **NFS server**, **HDFS** (on-cluster), and **JupyterHub** in the target layout (see [Lab_Topology_and_Resources.md](Lab_Topology_and_Resources.md)).

**File System Layout**:
- **Ops Environment**: `/home/ansible/ops/`
- **Docker Volumes**: Standard Linux paths (`/var/lib/docker/volumes/`)
- **NFS Mounts**: `/mnt/spark/` (standard Linux mount point)
- **Certificate Access**: `/etc/ssl/certs/elastic/` (standard Linux location)

**Characteristics**:
- Standard Linux file system conventions
- Direct Docker volume access
- Standard NFS client behavior

### WSL (Windows Subsystem for Linux)

**Example (legacy)**: GaryPC WSL — not used for current lab topology; observability runs on Lab3.

**File System Layout**:
- **Ops Environment**: `/home/ansible/ops/` (WSL filesystem)
- **Docker Volumes**: WSL Docker Desktop volumes
- **NFS Mounts**: `/mnt/spark/` (if NFS client configured)
- **Certificate Access**: 
  - Container: `/etc/ssl/certs/elastic/`
  - Host: `/mnt/c/Volumes/certs/Elastic/` (Windows path mounted in WSL)

**Windows Path Integration**:
- Windows paths accessible via `/mnt/c/` mount point
- Docker Desktop runs in WSL2, volumes managed by Docker Desktop
- File system performance considerations for Windows paths

**Characteristics**:
- Linux-like environment with Windows integration
- Docker Desktop manages volumes
- Windows file system access via mount points

### Windows 11 Hosts

**Example (legacy)**: Windows host with Docker Desktop — not current primary architecture.

**File System Layout**:
- **Certificate Storage**: `C:\Volumes\certs\Elastic\` (Windows path)
- **Docker Access**: Via WSL2 backend (Docker Desktop)
- **File Sharing**: Windows paths accessible to WSL via `/mnt/c/`

**Characteristics**:
- Windows-native file system
- Docker runs in WSL2, not directly on Windows
- Certificates stored in Windows file system, accessed by WSL/containers

---

## File Distribution and Storage Locations

### File Type Definitions

**Application Binaries** are compiled executables and JAR files that are loaded into memory at application startup. These files change infrequently and require version control. Examples include Spark JAR files, custom listener JARs, and compiled executables. They are stored in `~/ansible/ops/[service]/` directories.

**Configuration Files** are static, versioned files that define service behavior and node-specific settings. These files are templated from source variables and deployed to match each node's requirements. Examples include `spark-defaults.conf`, `docker-compose.yml`, and service configuration files. They are stored in `~/ansible/ops/[service]/` directories.

**Runtime Data** consists of continuously generated files that require shared access across multiple nodes. These files are ephemeral and do not require version control. Examples include Spark event logs and application logs. They are stored on NFS at `/mnt/spark/events/` and `/mnt/spark/logs/`.

**Datasets** are large input files used by Spark jobs that need to be accessible from multiple nodes for read operations. These files are typically static or updated infrequently. Examples include CSV files, Parquet files, and other data sources. They are stored on NFS at `/mnt/spark/data/`.

**Spark Checkpoints** are state snapshots created by Spark streaming applications for fault tolerance. These files are written continuously and require shared access for recovery. They are stored on NFS at `/mnt/spark/checkpoints/`.

**Python Packages** are Python libraries and dependencies that should be embedded in container images rather than installed at runtime. Examples include PySpark, NumPy, and other Python dependencies. They are distributed via container images.

**Docker Images** are container images stored in a local registry. Examples include custom Spark images and observability stack images. They are distributed via registry at `[registry]:5000/`.

**Certificates** are SSL/TLS certificates used for secure communication between services. These are security-sensitive files that require version control and auditability. Examples include CA certificates, service certificates, and private keys. Source files are stored in `~/ansible/ops/observability/certs/`, with runtime copies in Docker volumes.

### Distribution Methods

| File Type | Storage Location | Distribution Method |
|-----------|-----------------|---------------------|
| Application Binaries | `~/ansible/ops/[service]/` | Ansible |
| Configuration Files | `~/ansible/ops/[service]/` | Ansible |
| Runtime Data | `/mnt/spark/events/`, `/mnt/spark/logs/` | NFS |
| Datasets | `/mnt/spark/data/` | NFS |
| Spark Checkpoints | `/mnt/spark/checkpoints/` | NFS |
| Python Packages | Container images | Ansible/Docker |
| Docker Images | `[registry]:5000/` | Registry |
| Certificates | `~/ansible/ops/observability/certs/` (source), Docker volumes (runtime) | Ansible |

---

## Certificate Architecture

### Certificate Storage Locations

Certificates follow a dual-path architecture to support both Elasticsearch's native structure and Linux standard locations.

#### Container Directory Structure

**Elasticsearch Native Structure** (in Docker volume `certs:`): `/usr/share/elasticsearch/config/certs/` containing `ca/` (ca.crt, ca.key, ca.srl), `certs.zip`, `es01/` (es01.crt, es01.key), `kibana/` (kibana.crt, kibana.key), and `grafana/` (grafana.crt, grafana.key).

**Linux Standard Structure** (for host-level access): `/etc/ssl/private/` (700 permissions, contains server.key and ca.key with 600 permissions) and `/etc/ssl/certs/` (755 permissions, contains server.crt, ca.crt, and chain.crt with 644 permissions).

#### Certificate Service Mappings

| Service | Host Mount Point | Container Mount Point | Purpose |
|---------|-----------------|----------------------|---------|
| **init-certs** | `certs:` | `/usr/share/elasticsearch/config/certs` | Generation |
| **init-certs** | `/etc/ssl/certs/elastic` or `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | Distribution |
| **elasticsearch** | `certs:` | `/usr/share/elasticsearch/config/certs` | Access |
| **kibana** | `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | Access |
| **init-kibana-password** | `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | Access |
| **init-index** | `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | Access |
| **logstash** | `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | Access |
| **grafana** | `/mnt/c/Volumes/certs/Elastic` | `/etc/ssl/certs/elastic` | Access |
| **Elastic Agent (Linux)** | `/etc/ssl/certs/elastic/ca.crt` | N/A (host process) | Access |
| **Elastic Agent (Windows)** | `C:\Program Files\Elastic\Agent\ca.crt` | N/A (host process) | Access |

#### Certificate Flow (pull-based)

1. **Generation** (init-certs service):
   - Certificates generated into Docker volume `certs:` at `/usr/share/elasticsearch/config/certs/` (CA at `ca/ca.crt` and `ca.crt` at volume root).

2. **Distribution**:
   - **Single source of truth**: Docker volume on observability host. No separate publish to a host path.
   - **To Native Linux hosts**: Each app's install/start playbook fetches CA from the observability host's Docker volume; start playbooks test currency (hash) and re-fetch if stale. Local path: `/etc/ssl/certs/elastic/ca.crt`.
   - **To Containers**: Mounted from Docker volume `certs:` (e.g. at `/etc/ssl/certs/elastic`).

3. **Usage**:
   - **Elasticsearch**: Reads from Docker volume at `/usr/share/elasticsearch/config/certs/`.
   - **Other container services**: Mount certs volume; read CA from `/etc/ssl/certs/elastic/ca.crt`.
   - **Elastic Agent (Linux)**: Reads from `/etc/ssl/certs/elastic/ca.crt` (fetched from volume by install.yml; start.yml refreshes when stale). See `docs/CA_CERTIFICATE_ARCHITECTURE.md`.

#### Kubernetes Certificates

Kubernetes API server certificates are managed separately:
- **Location**: `/etc/kubernetes/pki/` on Kubernetes master node
- **Regeneration**: See `ansible/playbooks/k8s/regenerate_k8s_certs.yml`
- **SANs**: Includes cluster IPs, service names, and node hostnames

---

## File System Mappings

### DevOps → Ops Mapping

**Source**: `~/repos/spark-observability/[module]/`  
**Target**: `~/ansible/ops/[module]/`  
**Method**: Ansible playbooks (synchronize/copy tasks)

**Examples**:
- `~/repos/spark-observability/observability/` → `~/ansible/ops/observability/`
- `~/repos/spark-observability/elastic-agent/bin/gpu-metrics.py` → `~/ansible/ops/elastic-agent/bin/gpu-metrics.py` (if applicable)

### Ops → Docker Mapping

**Source**: `~/ansible/ops/observability/[service]/`  
**Target**: Container-specific paths (see Container Path Mappings table)  
**Method**: Docker Compose volume mounts

**Examples**:
- `~/ansible/ops/observability/elasticsearch/` → `/usr/share/elasticsearch/elasticsearch/` (in containers)
- `~/ansible/ops/observability/grafana/data/` → `/var/lib/grafana/data/` (in grafana container)

### NFS Mapping

**Source**: NFS server (`/srv/nfs/spark/` on the designated host; **target: Lab3**)  
**Target**: `/mnt/spark/` on all Kubernetes nodes  
**Method**: NFS mount (configured via Ansible)

**Subdirectory Mappings**:
- `/srv/nfs/spark/events/` → `/mnt/spark/events/` (Spark event logs)
- `/srv/nfs/spark/data/` → `/mnt/spark/data/` (Shared datasets)
- `/srv/nfs/spark/checkpoints/` → `/mnt/spark/checkpoints/` (Streaming checkpoints)
- `/srv/nfs/spark/logs/` → `/mnt/spark/logs/` (Application logs, per-host)

### Certificate Mapping

**Generation**: Docker volume `certs:` at `/usr/share/elasticsearch/config/certs/`  
**Distribution**: 
- Native Linux: `/etc/ssl/certs/elastic/ca.crt`
- WSL/Windows: `/mnt/c/Volumes/certs/Elastic/ca.crt`
- Containers: Mounted from volume or Windows path

---

## Best Practices

### For Development (DevOps User)

1. **Edit files in source repository**: Always edit files in `~/repos/spark-observability/`
2. **Regenerate .env**: Run `bash vars/generate_contexts.sh -f observability` after changing `vars/variables.yaml`
3. **Test locally**: Use Docker Compose from the source repository directory
4. **Commit changes**: Commit all changes to Git before deploying

### For Deployment (Ansible Operations)

1. **Use playbooks**: Always deploy using Ansible playbooks, never manually copy files
2. **Verify paths**: Ensure `~/ansible/ops/` exists and has correct permissions
3. **Check ownership**: Verify directories have appropriate ownership (ansible:ansible for most, 472:472 for Grafana)
4. **Monitor volumes**: Check Docker volumes are created and accessible

### For Container Runtime

1. **Use environment variables**: Scripts should use environment variables (e.g., `ES_*`), not hardcoded paths
2. **Respect volume mounts**: Write persistent data to Docker volumes, not bind mounts
3. **Handle permissions**: Ensure container user has appropriate permissions for mounted directories
4. **Validate paths**: Scripts should validate required paths exist before use

### For NFS Storage

1. **Mount NFS on all nodes**: Via Ansible playbooks
2. **Use subdirectories**: For organization (`/mnt/spark/events`, not `/mnt/events`)
3. **Configure autofs**: For automatic remounting on failure
4. **Monitor NFS health**: Disk space, mount status
5. **Implement log rotation**: To prevent disk fill
6. **Backup critical data**: Checkpoints, not logs
7. **Use NFS v4**: For better performance and security

### For Application Binaries (Ansible Distribution)

1. **Build locally** or on dedicated build node
2. **Store in Git** (if < 10MB) or Git LFS (if > 10MB)
3. **Deploy via Ansible** to consistent path on all nodes
4. **Version in filename** (e.g., `spark-otel-listener-1.0.0.jar`)
5. **Test on subset of nodes** before full deployment
6. **Document in playbook** (build → deploy → restart)
7. **Use checksum verification** to detect corruption

### For Configuration Files (Ansible Distribution)

1. **Use Jinja2 templates** (`.j2` files)
2. **Store in Git** with full history
3. **Generate from vars/variables.yaml** via `generate_contexts.sh` (wrapper) or `generate_contexts.py`
4. **Deploy via Ansible** with validation
5. **Restart services** after configuration changes
6. **Test configuration syntax** before deployment

### For Docker Images (Registry)

1. **Build on registry host** (local registry)
2. **Tag with version** (`[registry]:5000/spark:4.0.1`)
3. **Push to local registry** (`docker push`)
4. **Configure containerd** to allow insecure HTTP to local registry
5. **Pull on managed nodes** via Kubernetes/Ansible
6. **Use image digests** for reproducibility

---

## Future Considerations

### GitOps Approach
- Consider **FluxCD** or **ArgoCD** for automated Git → Kubernetes deployment
- Application binaries in Git → auto-deployed to Kubernetes ConfigMaps → mounted into pods
- Eliminates manual Ansible step, pure Git-driven deployments

### Object Storage (S3/MinIO)
- For **large datasets** (> 1GB), consider object storage instead of NFS
- Better performance for read-heavy workloads
- S3-compatible API (boto3, spark-hadoop-cloud connector)
- Pay-per-use scaling instead of fixed NFS capacity

### Container Image Optimization
- **Embed JARs in Docker image** instead of external distribution
- Build custom Spark image with OTel listener included
- Eliminates deployment step, pure image pull
- Trade-off: Image rebuild on every JAR update

---

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
2. Check ownership of directories (ansible:ansible for most, 472:472 for Grafana)
3. Verify Docker volume permissions
4. Check SELinux/AppArmor policies (if applicable)

### Variable Resolution Issues

**Symptom**: Script uses wrong paths or can't find files

**Check**:
1. Verify environment variables in `docker-compose.yml`
2. Check `.env` file is generated correctly from `vars/variables.yaml`
3. Verify context-specific variable values in `vars/variables.yaml`
4. Check script uses environment variables, not hardcoded paths

### NFS Distribution Issues

**Symptom**: Stale NFS mount or permission denied

**Check**:
1. Verify NFS server is running and accessible
2. Check NFS exports (`/etc/exports`) and squash settings
3. Verify mount point exists and is mounted (`mount | grep nfs`)
4. Check file permissions on NFS server

### Ansible Distribution Issues

**Symptom**: JAR not found on some nodes or version mismatch

**Check**:
1. Run deployment playbook again with `--diff` to show changes
2. Verify versioned filenames are consistent
3. Check ownership (should be `ansible:ansible`)
4. Use checksum verification in playbook

---

## Related Documentation

- **[Lab_Topology_and_Resources.md](Lab_Topology_and_Resources.md)**: Lab roles, service placement, resource caps
- **[Variable_Flow.md](Variable_Flow.md)**: Variable definition and flow
- **[Log_Architecture.md](Log_Architecture.md)**: Log file system organization
- **[Application_Locations.md](Application_Locations.md)**: Application installation locations
- **[Environment.md](Environment.md)**: Environment variable best practices
- **[Elastic_API_Client.md](../observability/elasticsearch/docs/Elastic_API_Client.md)**: API client usage
- **[Elasticsearch_indices.md](../observability/elasticsearch/docs/Elasticsearch_indices.md)**: Elasticsearch index catalog
- **[Elastic_Agent_Architecture.md](../elastic-agent/docs/Elastic_Agent_Architecture.md)**: Elastic Agent file system details

