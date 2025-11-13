# Elastic API Client Commands

## Overview

`esapi` and `kapi` are shell wrapper commands for interacting with Elasticsearch and Kibana REST APIs. They provide a structured exit code system that enables robust, idempotent shell scripts with conditional logic based on resource existence.

## Benefits

1. **Ease of Use**: Elide common parameters to curl, by leveraging environment variables 
2. **Robustness**: Structured exit codes handle all failure modes explicitly
2. **Idempotency**: Scripts can safely check for resource existence before creating
3. **Maintainability**: Clear exit codes make debugging and error handling easier
4. **Flexibility**: Enables complex conditional logic in shell scripts (if/then/else)
5. **Simplicity**: Single command replaces multi-line `curl` invocations
6. **Authentication**: Credentials and certificates managed centrally via environment variables

## Prerequisite 
Ensure the following environment variables are configured.

For Elasticsearch:
- ELASTIC_HOST: Elasticsearch hostname
- ELASTIC_PORT: Elasticsearch port
- ELASTIC_USER: Username for authentication
- ELASTIC_PASSWORD: Password for authentication
- CA_CERT: Path to CA certificate file

For Kibana:
- KIBANA_HOST: Kibana hostname
- KIBANA_PORT: Kibana port
- ELASTIC_USER: Username for authentication (kibana uses elastic user)
- KIBANA_PASSWORD: Password for authentication
- CA_CERT: Path to CA certificate file

## Command Usage

### Basic Syntax

```bash
# Elasticsearch API
esapi [FLAGS] METHOD ENDPOINT [JSON_FILE]

# Kibana API
kapi [FLAGS] METHOD ENDPOINT [JSON_FILE]
```

### Examples

```bash
# GET request
esapi GET /_cat/indices

# POST with inline JSON
esapi POST /_index_template/my-template template.json

# PUT with JSON file
kapi PUT /api/saved_objects/index-pattern/my-pattern pattern.json

# DELETE request
esapi DELETE /_transform/old-transform
```

## Exit Codes

| Code | Meaning | Use Case | Example |
|------|---------|----------|---------|
| 0 | Success | API call succeeded (HTTP 200) | Resource created, retrieved successfully |
| 1 | Expected Error | 4xx client error with `--allow-errors` | Resource not found (404), already exists (400) |
| 2 | Unexpected Error | 5xx server error or error without `--allow-errors` | Server internal error, unavailable |
| 3 | System Failure | Network error, connection refused | Service down, DNS failure |

## Flags

### `--noauth`

**Purpose**: Health checks without credentials

**Behavior**: HTTP 401/403 treated as success (service is responding)

**Exit Code**: 0 if service responds with 200/401/403

**Example**:
```bash
# Wait for Elasticsearch to be available
while ! esapi --noauth GET /; do
  echo "Waiting for Elasticsearch..."
  sleep 5
done
echo "Elasticsearch is up!"
```

### `--allow-errors`

**Purpose**: Conditional logic based on resource existence

**Behavior**: 4xx errors don't fail the script (exit 1 instead of 2)

**Exit Code**: 1 for 4xx, allowing shell conditionals

**Example**:
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

## Common Patterns

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
# Stop and delete if exists (ignore errors)
esapi --allow-errors DELETE /_transform/my-transform?force=true > /dev/null 2>&1 || true

# Create (works whether it existed or not)
esapi PUT /_transform/my-transform transform.json
```

### Conditional Creation

```bash
if ! esapi --allow-errors GET /_index_template/my-template > /dev/null 2>&1; then
  echo "Template doesn't exist, creating..."
  esapi PUT /_index_template/my-template template.json
else
  echo "Template already exists, skipping..."
fi
```

### Idempotent Resource Management

```bash
# Check if resource exists
if esapi --allow-errors GET /_data_stream/my-stream > /dev/null 2>&1; then
  if [ $? -eq 0 ]; then
    echo "Data stream exists, updating configuration..."
    # Update logic here
  else
    echo "Data stream does not exist, creating..."
    esapi PUT /_data_stream/my-stream stream.json
  fi
fi
```

### Wait for Resource to be Ready

```bash
# Wait for index to have documents
while ! esapi GET /my-index/_count | jq -e '.count > 0' > /dev/null 2>&1; do
  echo "Waiting for data..."
  sleep 10
done
echo "Index has data!"
```

## Configuration

Both commands read configuration from environment variables:

```bash
# Elasticsearch
export ELASTIC_URL="https://GaryPC.local:9200"
export ELASTIC_USER="elastic"
export ELASTIC_PASSWORD="your-password"
export CA_CERT_PATH="/path/to/ca.crt"

# Kibana
export KIBANA_URL="http://GaryPC.local:5601"
export KIBANA_USER="elastic"
export KIBANA_PASSWORD="your-password"
```

These are typically sourced from `observability/.env` in initialization scripts.

## Error Handling Best Practices

### Always Capture Exit Code

```bash
esapi GET /_cluster/health
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "Cluster health check failed with exit code: $EXIT_CODE"
  exit 1
fi
```

### Use --allow-errors for Conditional Logic

```bash
# Good: Uses --allow-errors for existence check
if esapi --allow-errors GET /_transform/my-transform > /dev/null 2>&1; then
  # Resource exists or other success
fi

# Bad: Without --allow-errors, 404 will cause script to fail
if esapi GET /_transform/my-transform > /dev/null 2>&1; then
  # Script exits on 404 before reaching this line
fi
```

### Handle Specific Exit Codes

```bash
esapi --allow-errors POST /_transform/my-transform/_start
RESULT=$?

case $RESULT in
  0)
    echo "✅ Transform started successfully"
    ;;
  1)
    echo "⚠️  Transform already running or source index missing (expected)"
    ;;
  2)
    echo "❌ Server error - check Elasticsearch logs"
    exit 1
    ;;
  3)
    echo "❌ Cannot connect to Elasticsearch"
    exit 1
    ;;
esac
```

## Related Files

- `observability/elasticsearch/bin/elastic_api.py` - Python API client with exit code system
- `observability/elasticsearch/bin/esapi` - Shell wrapper for Elasticsearch
- `observability/elasticsearch/bin/kapi` - Shell wrapper for Kibana
- `observability/elasticsearch/bin/init-index.sh` - Example usage in initialization script
