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

### CoreDNS on K8s
Where Kubernetes resolves GaryPC.local:
- Inside the OTel collector pods, when the Elasticsearch exporter connects to GaryPC.local:9200.
- The error lookup GaryPC.local on 10.96.0.10:53: no such host shows it’s using CoreDNS (10.96.0.10:53), not mDNS.

Why mDNS doesn’t work in Kubernetes pods:
1. Pods use CoreDNS, not the host’s DNS resolver.
1. CoreDNS doesn’t support mDNS (.local).
1. Pods run in isolated network namespaces, so mDNS multicast doesn’t reach them.

Best practices:
- Use Kubernetes Service names for internal communication (e.g., es01.observability.svc.cluster.local:9200).
- Use DNS names for external services when possible, but .local won’t work from pods.
- For external services outside the cluster:
   - Use proper DNS names (if available).
   - Use IP addresses as a fallback.
   - Or configure CoreDNS to forward .local queries to the host’s DNS.

**Current situation**:
* Elasticsearch runs in Docker Compose on GaryPC, not in Kubernetes.
* The OTel collector runs in Kubernetes and needs to reach Elasticsearch.

**Options**:
1. Use the IP address (current workaround: 192.168.1.115).
1. Configure CoreDNS to forward .local queries to the host DNS.
1. Create a Kubernetes Service/Endpoint pointing to the external Elasticsearch.
1. Use a proper DNS name if available.

**Recommendation**:
* Short term: Keep the IP address for now.
* Long term: Create a Kubernetes Service/Endpoint or configure CoreDNS to forward .local queries.


### Why `batch-events` works without `references` but `otel-traces` needs it

**Pattern 1: Direct index name (no references needed)**
- `batch-events.search.json`: `"index": "batch-events"`
- `batch-traces.search.json`: `"index": "batch-traces"`
- `spark-logs.search.json`: `"index": "spark-logs"`

**Pattern 2: Index reference (requires references section)**
- `otel-traces.search.json`: `"indexRefName": "kibanaSavedObjectMeta.searchSourceJSON.index"` + `references` array
- `spark-gc.search.json`: `"indexRefName": "..."` + `references`
- `metrics-spark-logs.search.json`: `"indexRefName": "..."` + `references`

#### Why the difference

1. Automatic resolution: When using `"index": "batch-events"`, Kibana resolves the data view by title/name if it exists. This works when:
   - The data view title matches the index name
   - The data view was created before the search
   - Kibana can find it automatically

2. Explicit references: When using `"indexRefName": "..."`, you must provide a `references` array because:
   - It references a saved object by ID (not name)
   - Kibana requires explicit linkage for saved object relationships
   - It’s the recommended approach for programmatic creation

3. Why `otel-traces` needs it: The working search references UUID `27af13a4-34fb-4057-b0be-12073ed7ac03`, which suggests:
   - The data view was created manually first (auto-generated UUID)
   - The search was created to reference that existing data view
   - Using `"index": "otel-traces"` didn’t resolve because the data view title didn’t match or wasn’t found

#### Best practice

Use `indexRefName` with `references` for:
- Programmatic creation via API
- Ensuring the search links to the correct data view
- Avoiding ambiguity when multiple data views match

The direct `"index": "..."` approach works when:
- The data view title exactly matches the index name
- The data view exists before the search is created
- You’re okay with Kibana’s automatic resolution

#### Recommendation

For consistency and reliability, update all search objects to use `indexRefName` with `references`. This ensures:
- Explicit linkage to data views
- Works regardless of data view creation order
- Aligns with Kibana’s saved objects model

Should I update the other search objects (`batch-events`, `batch-traces`, `spark-logs`) to use the `indexRefName` + `references` pattern for consistency?