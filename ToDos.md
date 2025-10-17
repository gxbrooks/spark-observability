# Project ToDos

## Security & Infrastructure

### Define Comprehensive Certificate Strategy

**Priority**: High  
**Status**: Not Started  
**Estimated Effort**: 2-3 days

**Description**:
Develop and document a comprehensive certificate management strategy for the entire Elastic-on-Spark platform. Currently, certificates are managed ad-hoc across different components, which creates security gaps and operational complexity.

**Scope**:

1. **Application SSL/TLS Certificates**
   - Elasticsearch (HTTPS API, inter-node communication)
   - Kibana (HTTPS UI)
   - Grafana (HTTPS UI)
   - Spark History Server (HTTPS UI)
   - JupyterHub (HTTPS UI - when re-enabled)

2. **Container Registry Certificates**
   - Docker registry on Lab2 (currently HTTP, should be HTTPS)
   - Certificate distribution to all cluster nodes
   - containerd/Docker daemon trust configuration

3. **Kubernetes Internal Certificates**
   - API server certificates
   - Kubelet certificates
   - Service account tokens
   - Pod-to-pod mTLS (service mesh consideration)

4. **Certificate Authority (CA) Architecture**
   - Root CA strategy (self-signed vs. enterprise CA)
   - Intermediate CAs for different trust domains
   - CA certificate distribution across Windows and Linux hosts

5. **Certificate Lifecycle Management**
   - Generation and signing process
   - Automated renewal strategy
   - Expiration monitoring and alerting
   - Revocation process

6. **Certificate Storage & Distribution**
   - Secure storage locations (avoid plain text in repos)
   - Kubernetes Secrets for runtime certificates
   - Ansible-based distribution for host-level certificates
   - Certificate synchronization between environments

**Current Pain Points**:
- Registry runs HTTP instead of HTTPS (current blocker for Spark 4.0)
- Elasticsearch CA certificate manually distributed
- No automated certificate rotation
- Self-signed certificates require manual trust configuration
- No centralized certificate inventory or expiration tracking

**Deliverables**:
1. **Architecture Document**: `docs/Certificate_Architecture.md`
   - Overall strategy and design decisions
   - Trust boundaries and certificate scopes
   - CA hierarchy diagram

2. **Implementation Playbooks**:
   - `ansible/playbooks/certificates/generate-ca.yml`
   - `ansible/playbooks/certificates/generate-app-certs.yml`
   - `ansible/playbooks/certificates/distribute-certs.yml`
   - `ansible/playbooks/certificates/rotate-certs.yml`

3. **Monitoring**:
   - Grafana dashboard for certificate expiration
   - Elasticsearch index for certificate inventory
   - Alerts for certificates expiring within 30 days

4. **Documentation**:
   - Certificate generation procedures
   - Trust configuration for new nodes
   - Troubleshooting guide

**Related Issues**:
- Spark 4.0 upgrade blocked by HTTP registry (tmp/996_spark40_upgrade_in_progress.md)
- Elasticsearch uses self-signed CA (observability/certs/init-certs.sh)
- JupyterHub would require HTTPS for production use

**Dependencies**:
- Decision on CA strategy (self-signed vs. Let's Encrypt vs. enterprise CA)
- Certificate naming conventions
- Key size and algorithm standards (RSA 2048/4096, ECDSA P-256, etc.)

**Success Criteria**:
- All external interfaces use HTTPS/TLS
- All internal registries use TLS
- Certificates auto-renew before expiration
- Zero manual certificate distribution steps
- All nodes trust the CA automatically
- Certificate expiration monitoring in place

---

## Future Enhancements

### Migrate to Spark 4.0 with Python 3.11
**Priority**: High  
**Status**: In Progress (95% complete - blocked by registry certificates)  
**Blockers**: Registry certificate configuration (see above)  
**Document**: tmp/996_spark40_upgrade_in_progress.md

### Re-enable JupyterHub for Multi-User Jupyter
**Priority**: Medium  
**Status**: Deferred  
**Prerequisites**: 
- Spark 4.0 upgrade completed
- Python 3.11 environment stabilized
- HTTPS certificate strategy implemented

### Spark History Server SparkListener for Direct Event Ingestion
**Priority**: Medium  
**Status**: Not Started  
**Description**: Replace file-based event log collection with direct SparkListener that pushes events to Elasticsearch via HTTP. This eliminates the need to parse event log files and provides real-time event ingestion.

---

**Last Updated**: 2025-10-16

