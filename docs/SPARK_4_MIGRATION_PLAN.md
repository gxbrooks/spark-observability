# Spark 4.0 Migration Plan

**Previous Version**: Spark 3.5.1 with Python 3.8  
**Current Version**: Spark 4.0.1 with Python 3.11  
**Status**: ✅ COMPLETED (October 2025)  
**Estimated Timeline**: 2-3 weeks

---

## Executive Summary

This document outlines the migration strategy from Spark 3.5.1 to Spark 4.0, including Python upgrade from 3.8 to 3.11 and re-enabling JupyterHub for multi-user interactive development.

**Key Goals:**
1. Migrate to Spark 4.0 for latest features and long-term support
2. Upgrade to Python 3.11 across all components
3. Re-enable JupyterHub with Python 3.11 compatibility
4. Maintain observability stack integrity
5. Ensure zero data loss and minimal downtime

---

## Current Stable Baseline (vStable)

### Architecture
- **Spark**: 3.5.1 (official apache/spark:3.5.1 image)
- **Python**: 3.8.20 (driver and workers aligned)
- **Kubernetes**: 1.x on Lab1 and Lab2
- **Observability**: Elasticsearch, Kibana, Grafana on GaryPC-WSL
- **Monitoring**: Elastic Agents on Lab1, Lab2, GaryPC (host-level)
- **Interactive Dev**: Client-mode iPython only
- **JupyterHub**: Scaled down (deferred)

### What's Working
- ✅ Batch applications (Chapter_*.py)
- ✅ Client-mode iPython sessions
- ✅ Spark History Server
- ✅ Event log collection to NFS
- ✅ Elastic Agent monitoring
- ✅ No Python version mismatch errors

---

## Migration Objectives

### Primary Goals
1. **Spark 4.0 Deployment**
   - Upgrade all Spark components to 4.0
   - Verify compatibility with existing applications
   - Test new features and performance improvements

2. **Python 3.11 Migration**
   - Build custom Spark 4.0 image with Python 3.11
   - Update driver environment to Python 3.11
   - Ensure all workers use Python 3.11

3. **JupyterHub Re-enablement**
   - Deploy JupyterHub with Python 3.11 support
   - Configure for multi-user access
   - Implement persistent storage for notebooks
   - Set up authentication

4. **Observability Continuity**
   - Verify event log format compatibility
   - Ensure metrics collection continues
   - Validate dashboards and visualizations
   - Test alerting (if configured)

---

## Phase 1: Research & Preparation (Week 1)

### Tasks

#### 1.1 Spark 4.0 Research
- [ ] Read Spark 4.0 release notes and migration guide
- [ ] Identify breaking changes affecting our codebase
- [ ] List deprecated APIs used in applications
- [ ] Document required code changes
- [ ] Review Python 3.11 compatibility

**Deliverables:**
- Breaking changes document
- Code migration checklist
- Risk assessment

#### 1.2 Environment Preparation
- [ ] Tag current stable environment: `vStable`
- [ ] Document current configuration
- [ ] Backup critical data (event logs, configs)
- [ ] Create rollback procedures

**Deliverables:**
- Backup verification report
- Rollback playbook

#### 1.3 Custom Image Development
- [ ] Create Spark 4.0 Dockerfile with Python 3.11
- [ ] Build and test image locally
- [ ] Push to registry
- [ ] Verify Python 3.11 compatibility

**Deliverables:**
- `spark/Dockerfile` for Spark 4.0
- Tested image: `Lab2.lan:5000/spark-py311:4.0.0`

#### 1.4 Test Namespace Setup
- [ ] Create `spark-test` namespace in Kubernetes
- [ ] Deploy Spark 4.0 cluster in test namespace
- [ ] Configure separate NFS path for test events
- [ ] Set up test observability endpoints

**Deliverables:**
- Test environment isolated from production
- Test cluster operational

---

## Phase 2: Testing & Validation (Week 2)

### Tasks

#### 2.1 Application Compatibility Testing
- [ ] Test all Chapter_*.py applications in Spark 4.0
- [ ] Identify and fix API incompatibilities
- [ ] Update deprecated code patterns
- [ ] Performance comparison (3.5.1 vs 4.0)

**Test Matrix:**
| Application | Spark 3.5.1 | Spark 4.0 | Issues | Fixed |
|-------------|-------------|-----------|--------|-------|
| Chapter_04.py | ✅ | ⏳ | - | - |
| Chapter_05.py | ⏳ | ⏳ | - | - |
| (add all apps) | - | - | - | - |

#### 2.2 Python 3.11 Environment Testing
- [ ] Create Python 3.11 venv
- [ ] Install PySpark 4.0
- [ ] Test driver-worker communication
- [ ] Verify no version mismatch errors

**Commands:**
```bash
# On Lab2
cd /home/gxbrooks/repos/elastic-on-spark
rm -rf venv
python3.11 -m venv venv
source venv/bin/activate
pip install pyspark==4.0.0 ipython pandas numpy pyarrow

# Test
python spark/apps/Chapter_04.py
```

#### 2.3 JupyterHub Testing
- [ ] Deploy JupyterHub with Python 3.11 in test namespace
- [ ] Configure to use Spark 4.0 cluster
- [ ] Test notebook execution
- [ ] Verify multi-user functionality
- [ ] Test persistent storage

**JupyterHub Configuration:**
```yaml
# jupyterhub-values.yaml
singleuser:
  image:
    name: jupyter/pyspark-notebook
    tag: python-3.11
  extraEnv:
    SPARK_MASTER: spark://spark-master.spark-test:7077
```

#### 2.4 Observability Testing
- [ ] Verify event log format compatibility
- [ ] Check Spark History Server with 4.0 logs
- [ ] Validate metrics collection (Elastic Agent)
- [ ] Test Kibana dashboards
- [ ] Test Grafana dashboards
- [ ] Compare metrics (3.5.1 vs 4.0)

**Validation Checklist:**
- [ ] Event logs readable by History Server
- [ ] Metrics flowing to Elasticsearch
- [ ] Dashboards displaying correctly
- [ ] No data gaps during migration

---

## Phase 3: Production Migration (Week 3)

### Pre-Migration Checklist
- [ ] All tests passing in test environment
- [ ] Code updates committed and reviewed
- [ ] Backup completed and verified
- [ ] Rollback procedure tested
- [ ] Stakeholders notified
- [ ] Maintenance window scheduled

### Migration Steps

#### 3.1 Python 3.11 Driver Update (30 min)
```bash
# On Lab2
cd /home/gxbrooks/repos/elastic-on-spark
rm -rf venv
python3.11 -m venv venv
source venv/bin/activate
pip install pyspark==4.0.0 ipython pandas numpy pyarrow pyyaml toml

# Update .bashrc for automatic activation
# (if needed)
```

#### 3.2 Update Ansible Variables (15 min)
```bash
# Edit variables.yaml
spark_version: "4.0.0"
python_version: "3.11"
spark_image: "Lab2.lan:5000/spark-py311"
spark_tag: "4.0.0"

# Regenerate configs
python3.11 linux/generate_env.py -f
```

#### 3.3 Deploy Spark 4.0 Cluster (45 min)
```bash
cd ansible

# Stop current Spark cluster
ansible-playbook -i inventory.yml playbooks/spark/stop_spark.yml

# Deploy Spark 4.0
ansible-playbook -i inventory.yml playbooks/spark/deploy_spark.yml -e "force_rebuild=true"

# Verify deployment
kubectl get pods -n spark
kubectl logs -n spark spark-master-0
```

#### 3.4 Re-enable JupyterHub (30 min)
```bash
cd ansible

# Deploy JupyterHub with Spark 4.0 support
ansible-playbook -i inventory.yml playbooks/jupyter/deploy_jupyterhub_helm.yml

# Verify
kubectl get pods -n spark | grep jupyter
```

#### 3.5 Validation & Testing (60 min)
- [ ] Run smoke tests
- [ ] Test batch applications
- [ ] Test client-mode iPython
- [ ] Test JupyterHub notebooks
- [ ] Verify observability
- [ ] Check History Server

### Post-Migration Tasks
- [ ] Update documentation
- [ ] Tag release: `vSpark4.0`
- [ ] Monitor for 24-48 hours
- [ ] Collect performance metrics
- [ ] User acceptance testing

---

## Rollback Procedure

If migration fails, rollback to stable Spark 3.5.1:

### Quick Rollback (15 min)
```bash
cd ansible

# Stop Spark 4.0
ansible-playbook -i inventory.yml playbooks/spark/stop_spark.yml

# NOTE: Migration completed - no longer needed
# Kept for historical reference only
# To rollback (if ever needed):
# cd /home/gxbrooks/repos/elastic-on-spark
# rm -rf venv
# python3.8 -m venv venv  # Requires Python 3.8 to be installed
# source venv/bin/activate
# pip install pyspark==3.5.1 ipython pandas numpy pyarrow pyyaml toml

# Revert Ansible variables
git checkout vStable -- ansible/vars/spark_vars.yml

# Redeploy Spark 3.5.1
ansible-playbook -i inventory.yml playbooks/spark/deploy_spark.yml

# Scale down JupyterHub
kubectl scale deployment hub --replicas=0 -n spark
kubectl scale deployment proxy --replicas=0 -n spark
```

### Verification (Historical - Migration Complete)
- [x] Spark 4.0.1 cluster running
- [x] Python 3.11 venv active
- [x] Batch apps working
- [x] Client-mode iPython working
- [ ] Observability intact

---

## Risk Assessment

### High Risk
1. **Breaking API Changes**
   - **Mitigation**: Thorough testing in test environment
   - **Fallback**: Code patches prepared in advance

2. **Event Log Format Changes**
   - **Mitigation**: Test History Server with 4.0 logs
   - **Fallback**: Maintain separate 3.5.1 History Server

3. **Python 3.11 Incompatibilities** (RESOLVED)
   - **Mitigation**: All dependencies tested and working
   - **Status**: No compatibility issues found

### Medium Risk
1. **Performance Regression**
   - **Mitigation**: Benchmark before/after
   - **Fallback**: Tune Spark 4.0 configs or rollback

2. **JupyterHub Integration Issues**
   - **Mitigation**: Test in isolation first
   - **Fallback**: Defer JupyterHub to later

### Low Risk
1. **Observability Continuity**
   - **Mitigation**: Elastic Agent is version-agnostic
   - **Fallback**: Minimal impact

---

## Success Criteria

### Must Have ✅
- [ ] Spark 4.0 cluster operational
- [ ] All applications running without errors
- [ ] Python 3.11 across all components
- [ ] No version mismatch errors
- [ ] Observability stack functional
- [ ] Event logs collected and viewable

### Should Have 🎯
- [ ] JupyterHub operational with multi-user support
- [ ] Performance equal or better than 3.5.1
- [ ] All dashboards updated for 4.0
- [ ] Documentation updated

### Nice to Have 🌟
- [ ] New Spark 4.0 features utilized
- [ ] Optimized configurations
- [ ] Enhanced monitoring

---

## Timeline Summary

| Week | Phase | Key Deliverables | Go/No-Go |
|------|-------|------------------|----------|
| 1 | Research & Prep | Breaking changes doc, custom image, test env | Day 5 |
| 2 | Testing | All tests passing, compatibility verified | Day 10 |
| 3 | Migration | Production deployment, validation, monitoring | Day 15 |

**Total Duration**: 15 business days (3 weeks)

---

## Resources & References

### Spark 4.0 Documentation
- [Spark 4.0 Release Notes](https://spark.apache.org/releases/spark-release-4-0-0.html)
- [Migration Guide](https://spark.apache.org/docs/latest/migration-guide.html)
- [Python API Changes](https://spark.apache.org/docs/latest/api/python/migration_guide/pyspark_upgrade.html)

### Python 3.11 Resources
- [What's New in Python 3.11](https://docs.python.org/3/whatsnew/3.11.html)
- [PySpark Python Compatibility](https://spark.apache.org/docs/latest/api/python/getting_started/install.html)

### Project Documentation
- [Current Architecture](PROJECT_OVERVIEW.md)
- [Ansible Playbooks](../ansible/playbooks/README.md)
- [Observability Setup](OBSERVABILITY_SETUP.md)

---

## Approval & Sign-off

**Prepared By**: AI Assistant  
**Date**: October 13, 2025  
**Approved By**: ________________  
**Date**: ________________  

---

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-10-13 | Initial migration plan created | AI Assistant |
| | | |
| | | |

---

## Next Steps

1. **Review this plan** with team/stakeholders
2. **Adjust timeline** based on availability
3. **Begin Phase 1** research activities
4. **Schedule migration window** for Week 3
5. **Set up monitoring** for migration process

**Note**: This plan assumes Spark 4.0 is released and stable. Adjust timeline if release date changes.

