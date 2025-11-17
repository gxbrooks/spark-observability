# File Distribution Strategy: NFS vs Ansible

## Executive Summary

This document outlines the strategy for distributing files across the cluster environment. The primary decision is between two distribution mechanisms:
1. **NFS (Network File System)**: Central shared storage
2. **Ansible**: Push-based file distribution

**Decision**: Use **Ansible for application binaries/JARs** and **NFS for runtime data**.

---

## Distribution Mechanisms

### NFS (Network File System)

**Characteristics**:
- Single source of truth (Lab2.local:/srv/nfs)
- Shared across all nodes via mount points
- Real-time synchronization (no deployment needed)
- Single point of failure
- Network I/O overhead on every access

**Strengths**:
- ✅ Automatic synchronization across all nodes
- ✅ No explicit deployment step required
- ✅ Easy to update (single location)
- ✅ Perfect for runtime data (logs, events, datasets)
- ✅ Supports concurrent writes from multiple nodes

**Weaknesses**:
- ❌ Network latency on every file access
- ❌ Single point of failure (NFS server down = cluster down)
- ❌ Not suitable for frequently accessed files (JARs loaded into memory)
- ❌ Potential stale mount issues
- ❌ Security: All nodes can access all NFS data

### Ansible

**Characteristics**:
- Push-based distribution from control node
- Files copied to local filesystem on each managed node
- Explicit deployment step required
- Local file access (no network overhead)
- Versioned, auditable deployments

**Strengths**:
- ✅ No network overhead during runtime
- ✅ Resilient: Each node has local copy
- ✅ Versioned: Explicit deployment with playbooks
- ✅ Auditable: Git history + Ansible logs
- ✅ Secure: Can control per-node file access
- ✅ Testable: Can deploy to subset of nodes first

**Weaknesses**:
- ❌ Requires explicit deployment step
- ❌ Potential version skew across nodes
- ❌ Not suitable for frequently changing data
- ❌ Requires automation for updates

---

## Decision Matrix

| File Type | Distribution Method | Rationale |
|-----------|-------------------|-----------|
| **Application Binaries** (JARs, executables) | **Ansible** | Loaded once at startup, infrequent updates, version control important |
| **Configuration Files** (spark-defaults.conf) | **Ansible** | Static, versioned, node-specific customization |
| **Runtime Data** (Spark events, logs) | **NFS** | Continuous writes, shared access needed, no version control |
| **Datasets** (input data for Spark jobs) | **NFS** | Large files, shared read access, no versioning |
| **Spark Checkpoints** (streaming) | **NFS** | Continuous writes, shared state, fault tolerance |
| **Python Packages** (pip install) | **Ansible** | Static, versioned, should be in container image |
| **Docker Images** | **Registry (Lab2.local:5000)** | Specialized distribution for containers |
| **Certificates** (SSL/TLS) | **Ansible** | Security-sensitive, versioned, auditable |

---

## Implementation: OpenTelemetry Listener

### Decision: Ansible Distribution

**File**: `spark-otel-listener-1.0.0.jar`

**Why Ansible?**
1. **Infrequent Updates**: JAR only changes when code is modified
2. **Version Control**: Each deployment is tracked in Git/Ansible logs
3. **Performance**: JAR loaded once into JVM memory at Spark startup
4. **Resilience**: Each node has local copy (no NFS dependency)
5. **Security**: Can be deployed only to authorized nodes
6. **Testability**: Can deploy to dev nodes first

**Deployment Path**:
- **Source**: `elastic-on-spark/spark/otel/spark-otel-listener-1.0.0.jar` (Git-tracked)
- **Destination**: `/home/ansible/spark/otel/spark-otel-listener-1.0.0.jar` (per managed node)

**Workflow**:
```bash
# 1. Build (local)
ansible-playbook -i inventory.yml playbooks/spark/build-otel-listener.yml

# 2. Deploy to managed nodes (Ansible push)
ansible-playbook -i inventory.yml playbooks/spark/deploy-otel-listener.yml

# 3. Restart Spark to load new JAR
ansible-playbook -i inventory.yml playbooks/spark/stop.yml
ansible-playbook -i inventory.yml playbooks/spark/start.yml
```

**Why NOT NFS?**
- ❌ JAR file accessed on every Spark job launch → network latency
- ❌ No benefit from automatic synchronization (updates are rare)
- ❌ Single point of failure for critical application code
- ❌ Stale NFS mount could break all Spark jobs

---

## Implementation: Runtime Data

### Decision: NFS Distribution

**Files**: Spark event logs, application logs, GC logs

**Why NFS?**
1. **Continuous Writes**: Logs written continuously during job execution
2. **Shared Access**: Multiple Spark executors writing, Elastic Agent reading, History Server reading
3. **No Versioning Needed**: Logs are ephemeral, not versioned artifacts
4. **Centralized Monitoring**: Elastic Agent on one node can read logs from all executors
5. **Fault Tolerance**: Spark History Server needs access to all event logs

**NFS Mount Path**:
- **Server**: `Lab2.local:/srv/nfs/spark`
- **Mount Point**: `/mnt/spark` on all nodes
- **Subdirectories**:
  - `/mnt/spark/events` - Spark event logs
  - `/mnt/spark/data` - Shared datasets
  - `/mnt/spark/checkpoints` - Streaming checkpoints

**Why NOT Ansible?**
- ❌ Logs written continuously (thousands of writes per job)
- ❌ Ansible is push-based, logs need to be pulled/collected
- ❌ No version control needed for ephemeral logs
- ❌ Shared access pattern (multiple writers, multiple readers)

---

## Best Practices

### For Application Binaries (Ansible)
1. **Build locally** or on dedicated build node
2. **Store in Git** (if < 10MB) or Git LFS (if > 10MB)
3. **Deploy via Ansible** to consistent path on all nodes
4. **Version in filename** (e.g., `spark-otel-listener-1.0.0.jar`)
5. **Test on subset of nodes** before full deployment
6. **Document in playbook** (build → deploy → restart)
7. **Use checksum verification** to detect corruption

### For Runtime Data (NFS)
1. **Mount NFS on all nodes** via Ansible
2. **Use subdirectories** for organization (`/mnt/spark/events`, not `/mnt/events`)
3. **Configure autofs** for automatic remounting on failure
4. **Monitor NFS health** (disk space, mount status)
5. **Implement log rotation** to prevent disk fill
6. **Backup critical data** (checkpoints, not logs)
7. **Use NFS v4** for better performance and security

### For Configuration Files (Ansible)
1. **Use Jinja2 templates** (`.j2` files)
2. **Store in Git** with full history
3. **Generate from vars/variables.yaml** via `generate_env.py`
4. **Deploy via Ansible** with validation
5. **Restart services** after configuration changes
6. **Test configuration syntax** before deployment

### For Docker Images (Registry)
1. **Build on Lab2** (local registry host)
2. **Tag with version** (`lab2.local:5000/spark:4.0.1`)
3. **Push to local registry** (`docker push`)
4. **Configure containerd** to allow insecure HTTP to local registry
5. **Pull on managed nodes** via Kubernetes/Ansible
6. **Use image digests** for reproducibility

---

## Migration Path

If a file type needs to move from NFS to Ansible (or vice versa):

### NFS → Ansible
1. Create Ansible playbook to copy file
2. Update references (paths in configs)
3. Test on dev node
4. Deploy to all nodes
5. Remove from NFS
6. Remove NFS mount (if no longer needed)

### Ansible → NFS
1. Create NFS directory
2. Copy file to NFS server
3. Update references (paths in configs)
4. Test on dev node
5. Remove local copies (via Ansible playbook)

---

## Troubleshooting

### Ansible Distribution Issues

**Problem**: JAR not found on some nodes  
**Solution**: Run deployment playbook again  
**Prevention**: Add verification step to playbook  

**Problem**: Version mismatch across nodes  
**Solution**: Run deployment playbook with `--diff` to show changes  
**Prevention**: Use versioned filenames  

**Problem**: Permission denied  
**Solution**: Check ownership (should be `ansible:ansible`)  
**Prevention**: Use `owner` and `group` in Ansible `copy` task  

### NFS Distribution Issues

**Problem**: Stale NFS mount  
**Solution**: `sudo umount /mnt/spark && sudo mount -a`  
**Prevention**: Configure autofs  

**Problem**: Permission denied on NFS  
**Solution**: Check NFS exports (`/etc/exports`) and squash settings  
**Prevention**: Use `no_root_squash` for trusted networks  

**Problem**: File not visible immediately  
**Solution**: NFS caching issue - `ls -l` to refresh  
**Prevention**: Use `sync` mount option  

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

## Conclusion

**Recommended Strategy**:
- **Application Binaries (JARs, executables)**: Ansible distribution to local filesystem
- **Runtime Data (logs, events, datasets)**: NFS for shared access
- **Configuration Files**: Ansible with Jinja2 templates
- **Docker Images**: Local registry (Lab2.local:5000)

**Key Principle**: **Match distribution mechanism to access pattern**
- **Static, versioned, infrequent access**: Ansible
- **Dynamic, continuous, shared access**: NFS
- **Container images**: Registry

This strategy balances **performance** (local file access), **resilience** (no single point of failure for binaries), **simplicity** (NFS for shared data), and **auditability** (Git + Ansible for versioned artifacts).

