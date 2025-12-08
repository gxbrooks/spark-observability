# CA Certificate Architecture for Elastic Stack in Multi-Host Environment

**Version**: 2.0  
**Date**: October 22, 2025  
**Status**: Active

## Executive Summary

This document defines the architecture for managing the Elastic Stack CA certificate (`ca.crt`) across a multi-host environment with Docker containers on Windows/WSL and Kubernetes deployments on Linux. The architecture uses a **pull-based model** where services fetch certificates from a standard published location rather than having certificates pushed to them.

## Design Principles

1. **Pull-Based Distribution**: Services fetch certificates from a standard location rather than having them pushed
2. **Single Source of Truth**: CA certificate published once to a standard location
3. **Self-Service**: Each service responsible for obtaining required certificates
4. **OS Standards**: Adhere to Windows and Linux certificate storage conventions
5. **Layered Architecture**: Clear separation between orchestration and configuration layers
6. **Idempotency**: All operations safe to run multiple times

## Architecture Overview

### Pull-Based Model vs Push-Based

**Pull-Based (Implemented)**:
```
┌──────────────┐
│  init-certs  │  Generates & publishes CA cert to standard location
└──────┬───────┘  CA_CERT=/etc/ssl/certs/elastic/ca.crt
       │
       ▼
┌──────────────────────────────────────────────────────┐
│  Standard Published Location (CA_CERT variable)     │
│  /etc/ssl/certs/elastic/ca.crt                       │
│  (Docker volume: certs:/usr/share/elasticsearch/    │
│   config/certs/ca/ca.crt)                           │
└───────┬──────────────────┬───────────────────────────┘
        │                  │
        ▼                  ▼
┌───────────────┐  ┌──────────────┐
│ Elastic Agent │  │ Spark Client │  Each service fetches when needed
│  (via Ansible │  │  (on start)  │  from Docker volume or CA_CERT path
│   from volume)│  │              │
└───────────────┘  └──────────────┘
```

**Advantages**:
- ✅ **Scalable**: New services automatically fetch without central coordination
- ✅ **Decoupled**: Services independent of distribution mechanism
- ✅ **Self-Healing**: Services can re-fetch if certificate becomes invalid
- ✅ **Simple**: No complex distribution playbooks needed
- ✅ **Atomic**: Each service validates certificate after fetching

**Disadvantages**:
- ⚠️ Services must implement fetch logic
- ⚠️ Requires shared/accessible storage location
- ⚠️ Services may have stale certs until next restart

**Push-Based (Not Implemented)**:
```
Ansible orchestrates distribution to all known hosts
```

**Disadvantages**:
- ❌ Requires knowing all consumers upfront
- ❌ Tightly coupled to Ansible
- ❌ Complex to add new services
- ❌ Race conditions during updates
- ❌ Violates self-service principle

## Certificate Storage Architecture

### 1. Certificate Generation (Docker Container: `init-certs`)

**Location**: Inside `init-certs` container  
**Internal Path**: `/usr/share/elasticsearch/config/certs/ca/ca.crt` (hardcoded X-Pack requirement)  
**Published Path**: `/etc/ssl/certs/elastic/ca.crt` (defined by `CA_CERT` variable)

**Process**:
1. Checks for existing certificate and version hash
2. Regenerates if:
   - `--force` flag provided via `FORCE_REGEN=1` environment variable
   - Certificate missing or corrupted
   - Version hash mismatch
3. Validates certificate after generation
4. Publishes to `CA_CERT` path (standard location for all services)

**Volumes**:
- Named volume `certs:` for internal Elasticsearch use (Docker volume)
- Bind mount `/mnt/c/Volumes/certs/Elastic:/etc/ssl/certs/elastic` (for Windows/WSL access, optional)

**Security**:
- Private keys: 640 permissions (owner:rw group:r)
- Public certs: 644 permissions (world-readable)
- Directories: 755 permissions

**Script Reference**: See `observability/certs/init-certs.sh` for implementation details.

### 2. Standard Published Location

**Path**: `/etc/ssl/certs/elastic/ca.crt` (defined by `CA_CERT` variable in `vars/variables.yaml`)

This is the **Single Source of Truth** path where all services expect to find the CA certificate.

**Distribution Methods**:
1. **Docker Containers**: Mounted from host path (via docker-compose.yml)
2. **Linux Hosts**: Fetched via Ansible from Docker volume on observability host
3. **Windows/WSL**: Optional mount from `/mnt/c/Volumes/certs/Elastic` (if needed)

**Characteristics**:
- Single variable (`CA_CERT`) for all contexts
- Standard Linux certificate location (`/etc/ssl/certs/`)
- Readable by all users (644 permissions)
- Version-controlled via hash in `.certs_version` file
- Validated by `init-certs` during publishing

### 3. Service-Level Certificate Fetching

Each service is responsible for fetching and validating certificates from the standard location.

#### Elastic Agent (Linux Hosts)

**Fetch Location**: `/etc/ssl/certs/elastic/ca.crt`

**Fetch Mechanism**: During `elastic-agent/install.yml` playbook (pull-based model)
```yaml
- name: Get Docker volume mount point for certs
  delegate_to: "{{ groups['observability'][0] }}"
  shell: docker volume inspect observability_certs --format '{{ .Mountpoint }}'
  register: cert_volume_path
  
- name: Fetch Elasticsearch CA certificate from Docker volume
  delegate_to: "{{ groups['observability'][0] }}"
  fetch:
    src: "{{ cert_volume_path.stdout }}/ca/ca.crt"
    dest: "/tmp/elastic-ca-{{ inventory_hostname }}.crt"
    flat: yes
    
- name: Copy CA certificate to host
  copy:
    src: "/tmp/elastic-ca-{{ inventory_hostname }}.crt"
    dest: "/etc/ssl/certs/elastic/ca.crt"
    owner: root
    group: root
    mode: '0644'
```

**Advantages**:
- No WSL mount dependency
- Direct access to Docker volume (source of truth)
- Works on any Linux host
- Simple and reliable

**Validation**: After copy, verify with `openssl x509`

#### Spark Client (Java/Scala Applications)

**Fetch Location**: Java truststore (`$JAVA_HOME/lib/security/cacerts`)

**Fetch Mechanism**: Import CA certificate into Java truststore on each Spark client host

**Installation Process**:
```bash
# 1. Fetch CA certificate from observability host
ansible -i ansible/inventory.yml <spark-host> -m copy \
  -a "src=/mnt/c/Volumes/certs/Elastic/ca.crt dest=/etc/ssl/certs/elastic/ca.crt mode=0644" \
  --become

# 2. Import into Java truststore (requires sudo)
ansible -i ansible/inventory.yml <spark-host> -m shell \
  -a "keytool -import -trustcacerts -alias elastic-ca \
      -file /etc/ssl/certs/elastic/ca.crt \
      -keystore $JAVA_HOME/lib/security/cacerts \
      -storepass changeit -noprompt" \
  --become

# 3. Verify import
keytool -list -keystore $JAVA_HOME/lib/security/cacerts \
  -storepass changeit | grep elastic-ca
```

**Environment Variables**: No additional environment variables required. The Spark OTel listener's `EventEmitter` uses the standard Java truststore automatically.

**Hostname Resolution**: Elasticsearch certificate is issued for hostname `es01`. Add hostname mapping:
```bash
# Add to /etc/hosts on Spark client hosts
<observability-host-ip> es01

# Example:
192.168.1.115 es01
```

**Configuration in Spark Applications**:
```bash
spark-submit \
  --conf spark.extraListeners=com.elastic.spark.otel.OTelSparkListener \
  --jars spark-otel-listener-1.0.0.jar \
  --conf spark.executorEnv.ES_URL="https://es01:9200" \
  --conf spark.executorEnv.ES_USER="elastic" \
  --conf spark.executorEnv.ES_PASSWORD="myElastic2025" \
  your_app.py
```

**Development/Testing Mode**: For development environments with self-signed certificates, the `EventEmitter` includes a trust-all SSL context (disabled in production). See `spark/otel-listener/src/main/scala/com/elastic/spark/otel/EventEmitter.scala`.

#### Docker Containers (Observability Stack)

**Fetch Location**: Mounted directly from standard location

**Mount Configuration**:
```yaml
volumes:
  - /mnt/c/Volumes/certs/Elastic:/etc/ssl/certs/elastic
```

All containers (Kibana, Logstash, Grafana, init-index) mount the standard location directly.

### 4. Elasticsearch Container (Special Case)

**Container Path**: `/usr/share/elasticsearch/config/certs/ca/ca.crt`

**Mount**: Uses named volume `certs:/usr/share/elasticsearch/config/certs:ro`

**Rationale**: X-Pack security requires certificates in this specific location. The init-certs container generates certificates directly into this volume, so Elasticsearch reads them from the same volume without additional copying.

## Certificate Lifecycle

### Generation Triggers

Certificates are regenerated when:

1. **Force flag**: `FORCE_REGEN=1` environment variable set
2. **Missing certificate**: CA cert file doesn't exist
3. **Missing version**: Version hash file doesn't exist
4. **Hash mismatch**: Current cert doesn't match saved hash
5. **First run**: `done` marker file doesn't exist

### Validation Process

After generation, `init-certs.sh` validates the certificate:

```bash
# Verify certificate is valid X.509
openssl x509 -in "$CA_CERT_PATH" -noout -text > /dev/null 2>&1

# Display certificate details
openssl x509 -in "$CA_CERT_PATH" -noout -issuer
openssl x509 -in "$CA_CERT_PATH" -noout -dates
openssl x509 -in "$CA_CERT_PATH" -noout -fingerprint -sha256
```

**Failure Behavior**: If validation fails, `init-certs.sh` exits with code 1, preventing invalid certificates from being published.

### Service Restart Requirements

After certificate regeneration, services must be restarted to load new certificates:

**Pattern**: `stop.yml` → `start.yml`

```bash
# Stop services
ansible-playbook -i ansible/inventory.yml ansible/playbooks/elastic-agent/stop.yml

# Start services (will fetch latest cert)
ansible-playbook -i ansible/inventory.yml ansible/playbooks/elastic-agent/start.yml
```

**Why no restart.yml?**: Follows standard playbook pattern (install/start/stop/diagnose/uninstall). A restart is simply stop + start.

## Playbook Architecture

### Standard Playbook Pattern

All playbooks follow this pattern:

- **install.yml**: Initial installation and configuration
- **start.yml**: Start services (validates prerequisites)
- **stop.yml**: Stop services gracefully
- **diagnose.yml** (or **status.yml**): Check service health
- **uninstall.yml**: Remove services and cleanup

### Observability Stack Playbooks

**observability/start.yml**:
```
1. Validate Docker available
2. Create required directories
3. Initialize certificates (docker compose up init-certs)
4. Validate CA certificate from published location
5. Start services (docker compose up -d)
6. Verify service health
```

**Key Feature**: Validates certificate from standard location rather than distributing it.

```yaml
- name: Validate CA certificate from published location
  stat:
    path: "/mnt/c/Volumes/certs/Elastic/ca.crt"
  register: ca_cert_stat
  
- name: Verify certificate is valid X.509
  shell: openssl x509 -in {{ ca_cert_path }} -noout -text
  register: ca_cert_validation
```

### Elastic Agent Playbooks

**elastic-agent/install.yml**:
```
1. Install Elastic Agent binary
2. Fetch CA certificate from standard location
3. Configure agent (elastic-agent.yml)
4. Create systemd service
5. Start service
```

**elastic-agent/start.yml**:
```
1. Start elastic-agent service
2. Verify service running
3. Display status
```

**elastic-agent/stop.yml**:
```
1. Stop elastic-agent service
2. Display status
```

## Certificate Regeneration Process

### Manual Regeneration

```bash
# 1. Stop observability platform
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/observability/stop.yml

# 2. Force regenerate certificates and start services
FORCE_REGEN=1 ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/observability/start.yml

# 3. Restart services on managed hosts (pull new cert)
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/elastic-agent/stop.yml
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/elastic-agent/start.yml
```

### Automatic Detection

Services automatically detect certificate changes:
- Elastic Agent: Checks cert during install/start
- Docker containers: Mount live directory, see changes on restart
- Spark: Validates cert before job submission

## Advantages & Trade-offs

### Pull-Based Architecture

**Advantages**:
1. **Scalability**: Adding new services doesn't require updating distribution logic
2. **Simplicity**: No complex orchestration for certificate distribution
3. **Fault Tolerance**: Services can re-fetch if certificate becomes corrupted
4. **Idempotency**: Services fetch same cert multiple times safely
5. **Decoupling**: Services independent of how certificates are generated
6. **Testability**: Each service's fetch logic can be tested independently

**Disadvantages**:
1. **Stale Certificates**: Services keep old cert until restarted
2. **Implementation Burden**: Each service must implement fetch logic
3. **Storage Requirement**: Requires shared/accessible storage location
4. **Discovery**: Services must know where to fetch certificates

**Mitigation Strategies**:
- Use consistent standard locations across all services
- Document fetch patterns for common service types
- Validate certificates after fetching
- Monitor certificate expiration proactively

### Sequential vs Parallel Flow

**Sequential (Implemented)**:
```
init-certs → validate → start services → health check
```

**Advantages**:
- Clear failure points
- Fast failure on cert problems
- Easy to debug
- Logs are clean and sequential

**Parallel Alternative**:
```
Start all services (including init-certs) → validate → restart if needed
```

**Why Not Used**:
- Race conditions possible
- Services may start with old certs
- More complex error recovery
- Only marginally faster

## File Permissions

| File Type | Permissions | Owner | Rationale |
|-----------|-------------|-------|-----------|
| `*.key` (Private Keys) | 640 | root:root | Elasticsearch (UID 1000) needs group read access |
| `*.crt` (Certificates) | 644 | root:root | Public keys, world-readable |
| `*.csr` (CSR files) | 644 | root:root | Intermediate files, can be public |
| Directories | 755 | root:root | Standard directory permissions |
| Published CA cert | 644 | root:root | Must be readable by all services |

**Critical**: Private keys must be 640 (not 600) because Elasticsearch runs as UID 1000 (not root) and needs group read access to keys in the Docker volume.

## Environment Variables

| Variable | Value | Usage |
|----------|-------|-------|
| `CA_CERT` | `/etc/ssl/certs/elastic/ca.crt` | **Single variable** for all contexts (containers and Linux hosts) |
| `FORCE_REGEN` | `1` or empty | Triggers force regeneration when set |

**Key Design**: `CA_CERT` is the **only** variable needed for CA certificate paths. All services use this single variable, eliminating the need for context-specific paths like `CA_CERT_LINUX_PATH` or `CA_CERT_PUBLISHED_PATH`.

**Elasticsearch Internal Paths**: The path `/usr/share/elasticsearch/config/certs` is hardcoded in `init-certs.sh` as it's a mandatory X-Pack requirement and cannot be parameterized.

## Adding New Services

To add a new service that needs the CA certificate:

1. **In install/start playbook**: Fetch certificate from standard location
   ```yaml
   - name: Fetch CA certificate
     fetch:
       src: "/mnt/c/Volumes/certs/Elastic/ca.crt"
       dest: "/path/to/service/ca.crt"
   ```

2. **Validate after fetch**:
   ```yaml
   - name: Validate certificate
     shell: openssl x509 -in /path/to/service/ca.crt -noout -text
   ```

3. **Configure service**: Point service to local copy of certificate

4. **No changes to init-certs or distribution logic required**

## Troubleshooting

### Issue: Service reports "certificate signed by unknown authority"

**Diagnosis**:
```bash
# Check if cert exists
ls -la /etc/ssl/certs/elastic/ca.crt

# Check if cert is valid
openssl x509 -in /etc/ssl/certs/elastic/ca.crt -noout -text

# Compare with published cert
md5sum /etc/ssl/certs/elastic/ca.crt
ansible -i ansible/inventory.yml GaryPC-WSL -m shell \
  -a "md5sum /mnt/c/Volumes/certs/Elastic/ca.crt"
```

**Resolution**:
```bash
# Re-run install to fetch latest cert
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/elastic-agent/install.yml
```

### Issue: Elasticsearch can't read private key

**Diagnosis**: Check logs for "not permitted to read"

**Root Cause**: Private key permissions too restrictive

**Resolution**: Regenerate with correct permissions (640)
```bash
FORCE_REGEN=1 ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/observability/start.yml
```

### Issue: Services using stale certificate

**Diagnosis**: Certificate regenerated but services still use old cert

**Resolution**: Restart services using stop + start pattern
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/SERVICE/stop.yml
ansible-playbook -i ansible/inventory.yml ansible/playbooks/SERVICE/start.yml
```

## Security Considerations

1. **Private Keys**: Never distributed; kept only in Docker volumes
2. **CA Certificate**: Public key safe to distribute broadly
3. **Storage Security**: Published location should be on trusted storage
4. **Access Control**: Only trusted processes should write to published location
5. **Validation**: Services must validate certificates after fetching
6. **Rotation**: Plan for certificate rotation before 10-year expiration
7. **Monitoring**: Alert on certificate expiration approaching
8. **Backup**: Back up CA private key for disaster recovery

## DNS and Network Stability

Certificate management depends on stable DNS resolution. See `docs/DNS_and_IP_Management.md` for:
- DHCP reservation configuration (recommended)
- Automated /etc/hosts management (fallback)
- Network diagnostics playbooks
- IP change detection and remediation

**Critical**: Always use DNS names (e.g., `GaryPC.lan`) in configurations, never IP addresses.

## Future Enhancements

1. **Certificate Monitoring**: Automated alerts for approaching expiration
2. **Kubernetes Integration**: ConfigMap/Secret for certificate distribution
3. **Automated Rotation**: Zero-downtime rotation procedure
4. **Version API**: RESTful API to check published certificate version
5. **Webhook Notifications**: Notify services when certificates regenerated

## References

- Elasticsearch X-Pack Security: https://www.elastic.co/guide/en/elasticsearch/reference/current/security-basic-setup.html
- Linux Certificate Standards: https://www.pathname.com/fhs/pub/fhs-2.3.html#ETCSSLCERTSRELATEDCA
- Docker Security Best Practices: https://docs.docker.com/engine/security/certificates/
- Pull-based Configuration Management: https://www.thoughtworks.com/insights/blog/push-vs-pull-configuration-management

## Change Log

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-09-30 | System | Initial architecture document |
| 1.1 | 2025-09-30 | System | Added implementation notes, verified deployment |
| 2.0 | 2025-10-22 | System | Refactored to pull-based model, removed push distribution, aligned with playbook patterns |
