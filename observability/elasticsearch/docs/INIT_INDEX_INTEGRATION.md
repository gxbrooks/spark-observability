# init-index.sh Integration Complete ✅

## Summary

All downsampling ILM policies have been integrated into `init-index.sh` so they can be created from source during Elasticsearch initialization.

## Changes Made

### 1. Modified `init-index.sh`

**File**: `/home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin/init-index.sh`

**Changes**:
- ✅ Fixed step numbering (STEP 2-4 labels corrected)
- ✅ Added **STEP 10**: Initialize Downsampling ILM Policies
  - Creates `system-metrics-downsampled` policy
  - Creates `docker-metrics-downsampled` policy
  - Creates `spark-gc-downsampled` policy
  - Creates `spark-logs-metrics-downsampled` policy
- ✅ Updated subsequent steps (STEP 11-13)
- ✅ Added helpful note about attaching policies to data streams

### 2. Created Helper Script

**File**: `/home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/system-metrics/attach-policies-to-datastreams.sh`

**Purpose**: Automatically attach downsampling policies to all relevant data streams

**Features**:
- Checks if data streams exist before attempting attachment
- Handles gracefully if data streams not yet created
- Color-coded output (green=success, yellow=warning, red=error)
- Provides verification commands after completion
- Uses `esapi` for consistent API interaction

### 3. Updated Documentation

Updated 4 documentation files to reflect init-index.sh integration:

#### a. `system-metrics/README.md`
- Added "Automatic (Recommended)" section for init-index.sh
- Documented `attach-policies-to-datastreams.sh` script
- Kept manual methods for reference

#### b. `QUICK_START_DOWNSAMPLING.md`
- Added "Option A: Fresh Installation" workflow
- Added "Option B: Existing Installation" workflow
- Reduced deployment time from 5 to 3 minutes

#### c. `DOWNSAMPLING_IMPLEMENTATION.md`
- Added "Method 1: Automatic" deployment steps
- Updated manual steps to use `attach-policies-to-datastreams.sh`
- Fixed command formatting consistency

#### d. `system-metrics/INTEGRATION_SUMMARY.md` (NEW)
- Comprehensive integration documentation
- Workflow diagrams
- File structure overview
- Testing timeline
- Troubleshooting guide

## Source-Controlled Files

All configuration is now in version control:

```
elasticsearch/
└── system-metrics/
    ├── system-metrics.ilm.json               # System metrics policy (JSON)
    ├── docker-metrics.ilm.json               # Docker metrics policy (JSON)
    ├── spark-gc.ilm.json                     # Spark GC policy (JSON)
    ├── spark-logs-metrics.ilm.json           # Spark log metrics policy (JSON)
    ├── README.md                             # Policy documentation
    ├── INTEGRATION_SUMMARY.md                # Integration overview
    ├── INIT_INDEX_INTEGRATION.md             # This file
    ├── apply-ilm-policies.sh                 # Manual application script
    ├── attach-policies-to-datastreams.sh     # NEW: Attachment script
    └── validate-downsampling.sh              # Validation script
```

## Usage

### Fresh Installation (Recommended)

```bash
# 1. Run init-index.sh (creates ILM policies in STEP 10)
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin
./init-index.sh

# 2. Attach policies to data streams
cd ../system-metrics
./attach-policies-to-datastreams.sh

# 3. Restart Grafana
cd /home/gxbrooks/repos/elastic-on-spark/observability
docker-compose restart grafana
```

### Existing Installation

```bash
# 1. Apply ILM policies manually
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/system-metrics
./apply-ilm-policies.sh

# 2. Attach policies to data streams
./attach-policies-to-datastreams.sh

# 3. Restart Grafana
cd /home/gxbrooks/repos/elastic-on-spark/observability
docker-compose restart grafana
```

### Validation

```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/system-metrics
./validate-downsampling.sh
```

## What Happens During init-index.sh

When you run `init-index.sh`, here's what happens in STEP 10:

```
=== STEP 10: INITIALIZING DOWNSAMPLING ILM POLICIES ===

Creating system-metrics-downsampled ILM policy...
Creating docker-metrics-downsampled ILM policy...
Creating spark-gc-downsampled ILM policy...
Creating spark-logs-metrics-downsampled ILM policy...

✅ Downsampling ILM policies initialized

NOTE: To enable downsampling on existing data streams, run:
  esapi PUT 'metrics-system.cpu-default/_settings' -d '{"index.lifecycle.name":"system-metrics-downsampled"}'
  esapi PUT 'metrics-docker.cpu-default/_settings' -d '{"index.lifecycle.name":"docker-metrics-downsampled"}'
  esapi PUT 'logs-spark_gc-default/_settings' -d '{"index.lifecycle.name":"spark-gc-downsampled"}'
  esapi PUT 'metrics-spark-logs-default/_settings' -d '{"index.lifecycle.name":"spark-logs-metrics-downsampled"}'
See: elasticsearch/system-metrics/README.md for details
```

Output files are created in `elasticsearch/outputs/`:
- `system-metrics-downsampled.ilm.out.json`
- `docker-metrics-downsampled.ilm.out.json`
- `spark-gc-downsampled.ilm.out.json`
- `spark-logs-metrics-downsampled.ilm.out.json`

## Benefits

### 1. Build from Source ✅
- All ILM policies created automatically during initialization
- No manual policy application needed
- Consistent configuration across environments

### 2. Version Control ✅
- JSON files in git repository
- Changes tracked and reviewable
- Easy rollback if needed

### 3. Reproducibility ✅
- Single command creates everything
- Ansible can orchestrate deployment
- CI/CD pipeline integration possible

### 4. Maintainability ✅
- Policies centrally defined
- Scripts handle complexity
- Documentation co-located with code

### 5. Automation ✅
- Helper scripts for common tasks
- Validation built-in
- Error handling and logging

## Data Streams Affected

### System Metrics (Elastic Agent)
- `metrics-system.cpu-default`
- `metrics-system.memory-default`
- `metrics-system.network-default`
- `metrics-system.diskio-default`
- `metrics-system.load-default`

### Docker Metrics (Elastic Agent)
- `metrics-docker.cpu-default`
- `metrics-docker.memory-default`
- `metrics-docker.network-default`

### Spark Metrics (Application)
- `logs-spark_gc-default`
- `metrics-spark-logs-default`

## Testing

Run `init-index.sh` and verify:

```bash
# 1. Check policies were created
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin
./esapi GET _ilm/policy/system-metrics-downsampled
./esapi GET _ilm/policy/docker-metrics-downsampled
./esapi GET _ilm/policy/spark-gc-downsampled
./esapi GET _ilm/policy/spark-logs-metrics-downsampled

# 2. Check output files
ls -lh elasticsearch/outputs/*downsampled*

# 3. Attach policies
cd ../system-metrics
./attach-policies-to-datastreams.sh

# 4. Validate
./validate-downsampling.sh
```

## Rollback

If you need to remove the downsampling policies:

```bash
cd /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin

# Delete policies
./esapi DELETE _ilm/policy/system-metrics-downsampled
./esapi DELETE _ilm/policy/docker-metrics-downsampled
./esapi DELETE _ilm/policy/spark-gc-downsampled
./esapi DELETE _ilm/policy/spark-logs-metrics-downsampled

# Detach from data streams
./esapi PUT 'metrics-system.cpu-default/_settings' -d '{"index.lifecycle.name":null}'
# ... (repeat for all data streams)
```

## Future Enhancements

Potential improvements:
- [ ] Auto-attach policies to data streams in init-index.sh
- [ ] Add retention policy variables to init-index.sh
- [ ] Create index templates with policies pre-configured
- [ ] Add monitoring/alerting for ILM execution
- [ ] Integrate with Ansible playbooks

## Support

For questions or issues:
- **Integration details**: This file
- **Policy documentation**: `system-metrics/README.md`
- **Quick start**: `../QUICK_START_DOWNSAMPLING.md`
- **Full implementation**: `../DOWNSAMPLING_IMPLEMENTATION.md`
- **Script source**: `init-index.sh` (STEP 10, lines 266-295)

## Verification Checklist

After running init-index.sh:

- [ ] STEP 10 executed without errors
- [ ] 4 policy output files created in `elasticsearch/outputs/`
- [ ] Policies visible in Elasticsearch: `GET _ilm/policy/*downsampled`
- [ ] Note displayed about attaching to data streams
- [ ] `attach-policies-to-datastreams.sh` executes successfully
- [ ] Grafana dashboard accessible at `/d/spark-system-metrics-aggregated`
- [ ] Dashboard shows data (after 30-60 minutes)

---

**Status**: ✅ Integration Complete
**Date**: 2025-11-12
**Version**: 1.1 (integrated into init-index.sh)

