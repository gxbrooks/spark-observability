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

### Modernize Batch Event Start-End Matching
**Priority**: Medium  
**Status**: Not Started  
**Estimated Effort**: 1-2 days

**Description**:
Replace the current Watcher-based polling approach for matching Spark batch event Start/End pairs with a more efficient on-demand lookup method using Elasticsearch 8.15 capabilities.

**Current Implementation**:
- **Mechanism**: Elasticsearch Watcher (`batch-match-join.watcher.json`)
- **Polling Interval**: Every 5 seconds
- **Query**: `has_parent` query to find unmatched End events with parent Start events
- **Actions**: Creates trace records in `batch-traces` and marks events as `matched: true`
- **Requirements**: Trial/Platinum license for Watcher functionality
- **Location**: `observability/elasticsearch/config/batch-events/match-join.watcher.json`

**Problems with Current Approach**:
- Polling overhead (runs every 5 seconds even when no events)
- 5-second latency between End event arrival and trace creation
- Watcher complexity and trial license requirement
- Resource usage from continuous polling
- Three watcher variants exist (match-join, match-join-error, match-mustache)

**Proposed Solutions** (Choose One):

**Option 1: Enrich Processor (Recommended)**
- Create enrich policy with Start events as source
- Use ingest pipeline to enrich End events on arrival
- Lookup by `start_event_uid` or `trace_id`
- Immediate matching (no polling delay)
- No license requirements beyond basic

**Option 2: Ingest Pipeline with Painless Script**
- Add ingest pipeline to `batch-events` template
- Use Painless script to lookup Start event when End arrives
- Calculate duration and create trace record inline
- Single-stage processing

**Option 3: Transform with Lookup**
- Continuous transform that processes new End events
- Uses scripted metric to lookup matching Start
- More resource-efficient than polling
- Better suited for batch processing

**Scope**:
1. Design and implement chosen approach
2. Create ingest pipeline or enrich policy configuration
3. Update `init-index.sh` to create new infrastructure
4. Test matching accuracy and performance
5. Migrate from Watcher to new approach
6. Update documentation
7. Deprecate/remove old Watcher files

**Benefits**:
- ✅ On-demand processing (no polling overhead)
- ✅ Lower latency (immediate vs 5-second delay)
- ✅ No trial license required
- ✅ Better resource utilization
- ✅ Simpler architecture
- ✅ Native ES 8.15 capabilities

**Deliverables**:
1. **Configuration Files**:
   - Enrich policy or ingest pipeline JSON
   - Updated batch-events template
   - Migration script from Watcher approach

2. **Updated Scripts**:
   - `init-index.sh` - Add new enrich/pipeline creation
   - Remove Watcher creation steps

3. **Documentation**:
   - `docs/Batch_Event_Matching.md` - New architecture
   - Update `docs/Elasticsearch_indices.md`
   - Update `docs/Spark_Jobs_Pane.md`

4. **Testing**:
   - Verify matching accuracy
   - Performance comparison (latency, resource usage)
   - Backward compatibility with existing batch-traces

**References**:
- Current implementation: `observability/elasticsearch/config/batch-events/`
- Documentation: `docs/Spark_Jobs_Pane.md` (lines 145-168)
- Index template: `observability/elasticsearch/config/batch-events/batch-events.template.json`

**Success Criteria**:
- 100% matching accuracy maintained
- < 1 second latency from End event to trace creation
- No polling overhead
- Works with basic Elasticsearch license
- Existing Grafana dashboards continue to function

---

**Last Updated**: 2025-11-12

