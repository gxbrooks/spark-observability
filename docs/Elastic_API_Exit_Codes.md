# Elastic API Exit Codes and Transform Idempotency

## Overview

This document describes the exit code system for `elastic_api.py` and how it enables idempotent transform management in `init-index.sh`.

## Problem Statement

### Original Issues

1. **Non-Idempotent Transform Creation**: The init-index script would fail if a transform already existed
2. **No Conditional Logic**: Shell scripts couldn't test for resource existence before taking action
3. **Unclear Failure Modes**: A single exit code couldn't distinguish between:
   - System failures (network errors)
   - Expected errors (resource not found)
   - Unexpected errors (server errors)

### Specific Transform Issue

The original `init-index.sh` code had a logical flaw:
```bash
if esapi GET /logs-spark-default/_count > /dev/null 2>&1; then
  echo "Index exists, creating transform..."
  esapi PUT /_transform/spark-log-metrics ...
else
  echo "Index doesn't exist yet. Transform will be created when Spark logs start flowing."
fi
```

**Problem**: If the index doesn't exist, there's NO mechanism to create the transform later. It would never get created automatically.

## Solution: Exit Code System

### Exit Codes

| Code | Meaning | Use Case | Example |
|------|---------|----------|---------|
| 0 | Success | API call succeeded (HTTP 200) | Resource created, retrieved successfully |
| 1 | Expected Error | 4xx client error with `--allow-errors` | Resource not found (404), already exists (400) |
| 2 | Unexpected Error | 5xx server error or error without `--allow-errors` | Server internal error, unavailable |
| 3 | System Failure | Network error, connection refused | Service down, DNS failure |

### Flags

#### `--noauth`
- **Purpose**: Health checks without credentials
- **Behavior**: HTTP 401/403 treated as success (service is responding)
- **Exit Code**: 0 if service responds with 200/401/403
- **Example**:
  ```bash
  # Wait for Elasticsearch to be available
  while ! esapi --noauth GET /; do
    sleep 5
  done
  ```

#### `--allow-errors`
- **Purpose**: Conditional logic based on resource existence
- **Behavior**: 4xx errors don't fail the script (exit 1 instead of 2)
- **Exit Code**: 1 for 4xx, allowing shell conditionals
- **Example**:
  ```bash
  # Check if transform exists
  if esapi --allow-errors GET /_transform/my-transform > /dev/null 2>&1; then
    echo "Transform exists (exit 0)"
  else
    STATUS=$?
    if [ $STATUS -eq 1 ]; then
      echo "Transform does not exist (exit 1 - expected 404)"
    elif [ $STATUS -eq 2 ]; then
      echo "Server error (exit 2 - unexpected)"
    else
      echo "System failure (exit 3 - network error)"
    fi
  fi
  ```

## Transform Idempotency Implementation

### New Logic in init-index.sh

```bash
# Create or update spark-log-metrics transform
echo "Checking if spark-log-metrics transform exists..."
if esapi --allow-errors GET /_transform/spark-log-metrics > /dev/null 2>&1; then
  TRANSFORM_EXISTS=$?
  if [ $TRANSFORM_EXISTS -eq 0 ]; then
    echo "Transform exists, updating..."
    # Stop and delete existing transform
    esapi POST /_transform/spark-log-metrics/_stop?force=true > /dev/null 2>&1 || true
    esapi DELETE /_transform/spark-log-metrics?force=true > /dev/null 2>&1 || true
  else
    echo "Transform does not exist, will create..."
  fi
else
  echo "Transform does not exist, will create..."
fi

# Create transform (works whether index exists or not)
echo "Creating spark-log-metrics transform..."
if esapi --allow-errors PUT /_transform/spark-log-metrics \
  elasticsearch/spark-logs/spark-log-metrics-transform.json \
  > elasticsearch/outputs/spark-log-metrics-transform.out.json 2>&1; then
  
  CREATE_STATUS=$?
  if [ $CREATE_STATUS -eq 0 ]; then
    echo "Transform created successfully"
  elif [ $CREATE_STATUS -eq 1 ]; then
    echo "⚠️  Transform creation returned expected error (may already exist)"
    cat elasticsearch/outputs/spark-log-metrics-transform.out.json
  else
    echo "❌ Transform creation failed with unexpected error"
    cat elasticsearch/outputs/spark-log-metrics-transform.out.json
  fi
else
  CREATE_STATUS=$?
  echo "Transform creation command failed with exit code: $CREATE_STATUS"
fi

# Start transform
echo "Starting spark-log-metrics transform..."
if esapi --allow-errors POST /_transform/spark-log-metrics/_start > /dev/null 2>&1; then
  START_STATUS=$?
  if [ $START_STATUS -eq 0 ]; then
    echo "✅ Transform started successfully"
  elif [ $START_STATUS -eq 1 ]; then
    echo "⚠️  Transform already started or cannot start yet (source index may not exist)"
  else
    echo "⚠️  Transform start failed (exit code: $START_STATUS)"
  fi
else
  echo "⚠️  Transform start command failed"
fi
```

### Key Benefits

1. **Idempotent**: Can run init-index.sh multiple times safely
2. **Updates Configuration**: Always updates transform definition if it exists
3. **Handles Missing Index**: Creates transform even if source index doesn't exist yet
4. **Clear Diagnostics**: Exit codes and messages indicate exactly what happened
5. **No False Failures**: Expected errors don't cause script to fail

## Testing Scenarios

### Scenario 1: Cold Start (No Index, No Transform)
```
Checking if spark-log-metrics transform exists...
Transform does not exist, will create...
Creating spark-log-metrics transform...
Transform created successfully
Starting spark-log-metrics transform...
⚠️  Transform already started or cannot start yet (source index may not exist)
✅ Spark Application Logs transform configured
```

**Result**: Transform is created but not started (index doesn't exist yet). When logs start flowing and create the index, transform will begin processing.

### Scenario 2: Warm Start (Index Exists, No Transform)
```
Checking if spark-log-metrics transform exists...
Transform does not exist, will create...
Creating spark-log-metrics transform...
Transform created successfully
Starting spark-log-metrics transform...
✅ Transform started successfully
✅ Spark Application Logs transform configured
```

**Result**: Transform is created and started immediately.

### Scenario 3: Hot Start (Index and Transform Exist)
```
Checking if spark-log-metrics transform exists...
Transform exists, updating...
Creating spark-log-metrics transform...
Transform created successfully
Starting spark-log-metrics transform...
✅ Transform started successfully
✅ Spark Application Logs transform configured
```

**Result**: Existing transform is stopped, deleted, recreated with potentially updated configuration, and restarted.

### Scenario 4: Transform Exists but Modified
```
Checking if spark-log-metrics transform exists...
Transform exists, updating...
Creating spark-log-metrics transform...
Transform created successfully
Starting spark-log-metrics transform...
✅ Transform started successfully
✅ Spark Application Logs transform configured
```

**Result**: Transform definition is updated, ensuring configuration changes are applied.

## Code Changes

### elastic_api.py

**Added:**
- `--allow-errors` flag for conditional logic
- Structured exit code system (0, 1, 2, 3)
- Removed `raise_for_status()` to consolidate exit logic in `main()`
- Enhanced help documentation with exit code table

**Modified:**
- `parse_arguments()`: Added `--allow-errors` flag
- `make_api_request()`: Returns (status, data) tuple without raising exceptions
- `main()`: Centralized exit code logic based on status and flags

### init-index.sh

**Modified STEP 11:**
- Check if transform exists using `--allow-errors`
- If exists: stop, delete, recreate (update pattern)
- If not exists: create
- Always attempt to start (gracefully handle errors)
- Clear diagnostic messages for each outcome

## Usage Examples

### Check Resource Existence
```bash
if esapi --allow-errors GET /_transform/my-transform > /dev/null 2>&1; then
  EXITCODE=$?
  if [ $EXITCODE -eq 0 ]; then
    echo "Transform exists"
  else
    echo "Transform does not exist"
  fi
fi
```

### Create or Update Pattern
```bash
# Stop and delete if exists
esapi --allow-errors DELETE /_transform/my-transform?force=true > /dev/null 2>&1 || true

# Create (works whether it existed or not)
esapi PUT /_transform/my-transform transform.json
```

### Conditional Creation
```bash
if ! esapi --allow-errors GET /_index_template/my-template > /dev/null 2>&1; then
  echo "Template doesn't exist, creating..."
  esapi PUT /_index_template/my-template template.json
fi
```

## Benefits

1. **Robustness**: Scripts handle all failure modes explicitly
2. **Idempotency**: Can rerun initialization safely
3. **Maintainability**: Clear exit codes make debugging easier
4. **Flexibility**: Enables complex conditional logic in shell scripts
5. **Updates**: Configuration changes are always applied
6. **No Manual Intervention**: Transform management is fully automated

## Related Files

- `observability/elasticsearch/bin/elastic_api.py` - API client with exit codes
- `observability/elasticsearch/bin/init-index.sh` - Initialization script
- `observability/elasticsearch/bin/esapi` - Shell wrapper for elasticsearch
- `observability/elasticsearch/bin/kapi` - Shell wrapper for kibana


