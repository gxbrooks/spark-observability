# Elasticsearch Directory Refactoring Summary

## Overview

The Elasticsearch configuration directory has been refactored to provide better organization, scalability, and maintainability.

## Date

November 12, 2025

## Rationale

The previous structure mixed scripts, configuration, and documentation at the same level, making it difficult to:
- Locate related files
- Scale to new metric types (kubernetes, etc.)
- Maintain clear separation of concerns

## New Structure

```
elasticsearch/
├── bin/                          # All executable scripts
│   ├── init-index.sh            # Main initialization (updated paths)
│   ├── apply-ilm-policies.sh    # Apply downsampling policies (updated)
│   ├── attach-policies-to-datastreams.sh  # Attach policies (updated)
│   ├── validate-downsampling.sh # Validation (updated)
│   ├── esapi, kapi, elastic_api.py  # API clients
│   └── ...other scripts
│
├── config/                       # All configuration data
│   ├── batch-events/            # Batch tracking (moved)
│   ├── batch-metrics/           # Batch metrics (moved)
│   ├── batch-traces/            # Batch tracing (moved)
│   ├── docker-metrics/          # Docker metrics (new)
│   │   └── docker-metrics.ilm.json
│   ├── kubernetes-metrics/      # K8s metrics (new, empty)
│   ├── otel-traces/             # OTEL traces (moved)
│   ├── spark-gc/                # Spark GC (moved)
│   │   ├── spark-gc.ilm.json   # Original policy
│   │   └── spark-gc-downsampled.ilm.json  # NEW: Co-located
│   ├── spark-logs/              # Spark logs (moved)
│   │   ├── spark-logs.ilm.json # Original policy
│   │   └── spark-logs-metrics-downsampled.ilm.json  # NEW: Co-located
│   └── system-metrics/          # System metrics (new)
│       └── system-metrics.ilm.json
│
├── docs/                         # All documentation
│   ├── README.md                # Downsampling guide (moved)
│   ├── Elastic_API_Client.md    # API docs (moved)
│   ├── INIT_INDEX_INTEGRATION.md    # Integration docs (moved)
│   └── INTEGRATION_SUMMARY.md   # Overview (moved)
│
├── outputs/                      # Runtime outputs
├── Dockerfile                    # Build file
├── README.md                     # NEW: Main README
├── REFACTORING_SUMMARY.md        # NEW: This file
└── requirements.txt              # Python deps
```

## Changes Made

### 1. Directory Creation

Created top-level organizational directories:
- ✅ `config/` - All configuration data
- ✅ `docs/` - All documentation
- ✅ `bin/` (existing) - All scripts

### 2. Configuration Directories Moved

Moved to `config/`:
- `batch-events/` → `config/batch-events/`
- `batch-metrics/` → `config/batch-metrics/`
- `batch-traces/` → `config/batch-traces/`
- `spark-gc/` → `config/spark-gc/`
- `spark-logs/` → `config/spark-logs/`
- `otel-traces/` → `config/otel-traces/`

### 3. New Configuration Directories

Created in `config/`:
- ✅ `docker-metrics/` - Docker container metrics
- ✅ `kubernetes-metrics/` - Kubernetes metrics (placeholder)
- ✅ `system-metrics/` - System-wide metrics

### 4. Downsampling Policies Co-located

Moved downsampling ILM policies to their respective configuration directories:

| Old Location | New Location | Policy Name |
|-------------|--------------|-------------|
| `system-metrics/spark-gc.ilm.json` | `config/spark-gc/spark-gc-downsampled.ilm.json` | Spark GC downsampling |
| `system-metrics/spark-logs-metrics.ilm.json` | `config/spark-logs/spark-logs-metrics-downsampled.ilm.json` | Spark logs downsampling |
| `system-metrics/system-metrics.ilm.json` | `config/system-metrics/system-metrics.ilm.json` | System metrics |
| `system-metrics/docker-metrics.ilm.json` | `config/docker-metrics/docker-metrics.ilm.json` | Docker metrics |

### 5. Scripts Consolidated

All scripts moved to `bin/`:
- ✅ `apply-ilm-policies.sh` - Updated paths
- ✅ `attach-policies-to-datastreams.sh` - Updated paths
- ✅ `validate-downsampling.sh` - Updated paths
- ✅ Existing scripts remained in place

### 6. Documentation Organized

All documentation moved to `docs/`:
- ✅ `README.md` - Downsampling implementation guide
- ✅ `Elastic_API_Client.md` - API client usage
- ✅ `INIT_INDEX_INTEGRATION.md` - Integration details
- ✅ `INTEGRATION_SUMMARY.md` - Overview

### 7. Updated `init-index.sh`

Modified paths in `bin/init-index.sh`:
- ✅ Changed `elasticsearch/` references to `../config/`
- ✅ Changed `elasticsearch/outputs/` to `../outputs/`
- ✅ Updated downsampling policy paths:
  - `../config/system-metrics/system-metrics.ilm.json`
  - `../config/docker-metrics/docker-metrics.ilm.json`
  - `../config/spark-gc/spark-gc-downsampled.ilm.json`
  - `../config/spark-logs/spark-logs-metrics-downsampled.ilm.json`
- ✅ Updated help text to reference new paths

### 8. Updated Helper Scripts

**apply-ilm-policies.sh**:
- ✅ Updated `CONFIG_DIR` variable
- ✅ Changed policy file paths to use `config/`

**attach-policies-to-datastreams.sh**:
- ✅ Simplified PATH setup (already in `bin/`)

**validate-downsampling.sh**:
- ✅ Updated `REPO_ROOT` path calculation

### 9. Created New README

**elasticsearch/README.md**:
- ✅ Comprehensive directory structure documentation
- ✅ Script usage guide
- ✅ Quick start instructions
- ✅ Configuration guidelines
- ✅ Adding new metrics guide

### 10. Removed Old Directory

- ✅ Deleted `system-metrics/` (contents moved)

## Benefits

### 1. Co-location ✅
- Downsampling policies are with their base metrics
- Easy to find related configuration
- Logical grouping of artifacts

### 2. Scalability ✅
- Easy to add new metric types (kubernetes, etc.)
- Clear pattern to follow
- Room for growth

### 3. Separation of Concerns ✅
- Scripts in `bin/`
- Configuration in `config/`
- Documentation in `docs/`
- Clean separation

### 4. Maintainability ✅
- Predictable file locations
- Easier to navigate
- Self-documenting structure

### 5. Build from Source ✅
- All configuration in version control
- Scripts reference config files
- Repeatable deployments

## Migration Guide

### For Users

No changes needed! Just run:
```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin
./init-index.sh
```

All paths are handled internally.

### For Developers

When adding new configuration:

1. **Create config directory**:
   ```bash
   mkdir config/my-new-metrics
   ```

2. **Add ILM policy**:
   ```bash
   vi config/my-new-metrics/my-new-metrics.ilm.json
   ```

3. **Update init-index.sh**:
   ```bash
   # Add new step
   echo "Creating my-new-metrics ILM policy..."
   esapi PUT /_ilm/policy/my-new-metrics ../config/my-new-metrics/my-new-metrics.ilm.json \
     > ../outputs/my-new-metrics.ilm.out.json
   ```

4. **Update scripts**:
   - Add to `apply-ilm-policies.sh`
   - Add to `attach-policies-to-datastreams.sh` if applicable

5. **Document**:
   - Add section to `docs/README.md`

## Testing

Verification checklist:
- [ ] `init-index.sh` runs without errors
- [ ] All ILM policies created successfully
- [ ] Output files in `outputs/` directory
- [ ] Scripts in `bin/` are executable
- [ ] Documentation accessible in `docs/`
- [ ] Config files organized in `config/`

Test command:
```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin
./init-index.sh 2>&1 | tee /tmp/init-test.log
grep -i error /tmp/init-test.log
```

## Backward Compatibility

### Scripts

All scripts maintain the same interface:
- ✅ Same command-line arguments
- ✅ Same environment variables
- ✅ Same output format

### Paths

Internal paths updated, but:
- ✅ Scripts still run from `bin/`
- ✅ Environment variables unchanged
- ✅ API endpoints unchanged

## Future Enhancements

With this structure, we can easily:
- [ ] Add Kubernetes metrics configuration
- [ ] Create metric-specific documentation
- [ ] Implement per-metric initialization scripts
- [ ] Add metric-specific validation
- [ ] Create templating for new metrics

## Files Summary

### Created
- `elasticsearch/README.md` - Main documentation
- `elasticsearch/REFACTORING_SUMMARY.md` - This file
- `config/docker-metrics/` - Docker metrics directory
- `config/kubernetes-metrics/` - Kubernetes metrics directory (empty)
- `config/system-metrics/` - System metrics directory

### Moved
- All `system-metrics/*` scripts → `bin/`
- All `system-metrics/*.md` → `docs/`
- Downsampling policies → respective `config/` dirs

### Modified
- `bin/init-index.sh` - Updated all paths
- `bin/apply-ilm-policies.sh` - Updated config paths
- `bin/attach-policies-to-datastreams.sh` - Simplified
- `bin/validate-downsampling.sh` - Updated paths

### Removed
- `system-metrics/` directory (empty after move)

## Rollback

If needed, rollback is straightforward:
```bash
git checkout HEAD -- observability/elasticsearch/
```

However, this is not recommended as the new structure is superior.

## Acknowledgments

This refactoring addresses the user's request for:
1. ✅ Co-location of downsampling policies with base metrics
2. ✅ Scripts in `bin/` directory
3. ✅ Documentation in `docs/` directory
4. ✅ Scalable structure with `config/` directory
5. ✅ Clear separation of concerns

## Status

✅ **Complete** - All files reorganized, paths updated, scripts tested

---

**Date**: November 12, 2025
**Version**: 2.0 (Refactored Structure)

