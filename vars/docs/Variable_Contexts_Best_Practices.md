# Variable Contexts Best Practices

## Executive Summary

This document describes best practices for managing variables in the `vars/variables.yaml` file and their relationship to contexts defined in `vars/contexts.yaml`. These practices ensure consistency, reduce complexity, and prevent order-of-execution issues.

## Core Principles

### 1. One Variable Name Per Entity

**Rule**: Each entity (e.g., Elasticsearch host, Logstash host) should have one and only one variable name, unless there is a compelling reason not to.

**Rationale**: Multiple variable names for the same entity create confusion, increase maintenance burden, and can lead to order-of-execution issues when variables reference each other.

**Example - Good**:
```yaml
ES_HOST:
  contexts: [observability, spark-runtime, devops, elastic-agent]
  values:
    observability: es01
    spark-runtime: GaryPC.local
    devops: GaryPC.local
    elastic-agent: GaryPC.local
```

**Example - Bad** (avoid):
```yaml
ELASTIC_HOST:
  contexts: [observability, devops]
  values:
    devops: ${ELASTIC_HOST_CLIENT}
    observability: es01
ELASTIC_HOST_CLIENT:
  value: GaryPC.local
  contexts: [spark-runtime, devops]
ELASTIC_HOST_EXTERNAL:
  value: GaryPC.local
  contexts: [elastic-agent]
```

### 2. Context-Specific Values

**Rule**: If a variable needs different values in different contexts, use the `values` dictionary with context-specific keys rather than creating separate variables.

**Rationale**: This keeps related values together, makes it clear they represent the same entity, and prevents variable proliferation.

**Example - Good**:
```yaml
LS_HOST:
  contexts: [observability, elastic-agent]
  values:
    observability: logstash01
    elastic-agent: GaryPC.local
```

**Example - Bad** (avoid):
```yaml
LS_HOST:
  value: logstash01
  contexts: [observability]
LS_HOST_EXTERNAL:
  value: GaryPC.local
  contexts: [elastic-agent]
```

### 3. Variable Extension (Path Building)

**Rule**: It is acceptable to use a variable to define another variable when extending the value (e.g., building paths).

**Rationale**: Path building is a common pattern and the extension makes the relationship clear.

**Example - Good**:
```yaml
ES_DIR:
  contexts: [devops, observability]
  values:
    devops: ${HOME}/repos/elastic-on-spark/observability/elasticsearch
    observability: /usr/share/elasticsearch/elasticsearch
ES_CONFIG_DIR:
  value: ${ES_DIR}/config
  contexts: [devops, observability]
```

### 4. Avoid Variable Aliasing Without Extension

**Rule**: Do not use variables to define other variables without extension. If a variable is simply an alias for another, consolidate them.

**Rationale**: Aliasing without extension indicates the variables should be consolidated, reducing complexity and potential order-of-execution issues.

**Example - Bad** (avoid):
```yaml
ES_USER:
  value: ${ELASTIC_USER}
  contexts: [devops, observability]
ELASTIC_USER:
  value: elastic
  contexts: [observability, spark-runtime, elastic-agent, devops]
```

**Example - Good** (consolidated):
```yaml
ES_USER:
  value: elastic
  contexts: [observability, spark-runtime, elastic-agent, devops]
```

### 5. Application Variable Name Mapping

**Rule**: If an application expects a different variable name than the standardized name in `variables.yaml`, map the variable in the deployment configuration (e.g., `docker-compose.yml`) rather than creating duplicate variables.

**Rationale**: This maintains a single source of truth while accommodating application-specific requirements.

**Example - Good**:
```yaml
# In variables.yaml
ES_PASSWORD:
  value: myElastic2025
  contexts: [observability, spark-runtime, elastic-agent, devops]
```

```yaml
# In docker-compose.yml
environment:
  # Map ES_* variables to ELASTIC_* for Elasticsearch service expectations
  ELASTIC_PASSWORD: ${ES_PASSWORD}
  ELASTIC_USER: ${ES_USER}
  ELASTIC_HOST: ${ES_HOST}
  ELASTIC_PORT: ${ES_PORT}
```

### 6. Standardized Naming Conventions

**Rule**: Use consistent prefixes for related variables:
- `ES_*` for Elasticsearch variables (ES already stands for Elasticsearch)
- `KIBANA_*` for Kibana variables
- `LS_*` for Logstash variables
- `SPARK_*` for Spark variables
- `OTEL_*` for OpenTelemetry variables

**Rationale**: Consistent naming makes it easier to find related variables and understand their purpose.

### 7. Context Consistency

**Rule**: All contexts referenced in `variables.yaml` should be defined in `contexts.yaml`. Remove references to undefined contexts.

**Rationale**: Undefined contexts cannot generate output files, leading to missing variables and potential runtime errors.

**Example - Bad** (avoid):
```yaml
# In variables.yaml
PYTHON_VERSION:
  contexts: [spark-runtime, client, managed-node, spark-client]
  # 'client' is not defined in contexts.yaml
```

**Example - Good**:
```yaml
# In variables.yaml
PYTHON_VERSION:
  contexts: [spark-runtime, managed-node, spark-client]
  # All contexts are defined in contexts.yaml
```

## Consolidation Patterns

### Pattern 1: Host Variables

**Before**:
```yaml
ELASTIC_HOST:
  contexts: [observability, devops]
  values:
    devops: ${ELASTIC_HOST_CLIENT}
    observability: es01
ELASTIC_HOST_CLIENT:
  value: GaryPC.local
  contexts: [spark-runtime, devops]
ELASTIC_HOST_EXTERNAL:
  value: GaryPC.local
  contexts: [elastic-agent]
```

**After**:
```yaml
ES_HOST:
  contexts: [observability, spark-runtime, devops, elastic-agent]
  values:
    observability: es01
    spark-runtime: GaryPC.local
    devops: GaryPC.local
    elastic-agent: GaryPC.local
```

### Pattern 2: Service-Specific Variables

**Before**:
```yaml
LS_HOST:
  value: logstash01
  contexts: [observability]
LS_HOST_EXTERNAL:
  value: GaryPC.local
  contexts: [elastic-agent]
```

**After**:
```yaml
LS_HOST:
  contexts: [observability, elastic-agent]
  values:
    observability: logstash01
    elastic-agent: GaryPC.local
```

### Pattern 3: Variable Aliasing

**Before**:
```yaml
ES_PORT:
  value: ${ELASTIC_PORT}
  contexts: [devops, observability]
ELASTIC_PORT:
  value: 9200
  contexts: [observability, spark-runtime, devops]
```

**After**:
```yaml
ES_PORT:
  value: 9200
  contexts: [observability, spark-runtime, devops]
```

## Variable-Context Grid

A variable-context grid helps visualize which variables are used in which contexts. This can be generated using:

```bash
python3 -c "
import yaml
from pathlib import Path

# Load variables
with open('vars/variables.yaml') as f:
    variables = yaml.safe_load(f)

# Load contexts
with open('vars/contexts.yaml') as f:
    contexts_data = yaml.safe_load(f)
    contexts = [ctx['name'] for ctx in contexts_data['contexts']]

# Build grid (see implementation above)
"
```

The grid helps identify:
- Variables that appear in many contexts (potential candidates for consolidation)
- Contexts with very few variables (potential candidates for removal)
- Variables that appear in only one context (may be context-specific)
- Missing context definitions

## When NOT to Consolidate

### Different Formats

Variables that represent the same concept but in different formats should NOT be consolidated.

**Example**:
```yaml
PYTHON_VERSION:
  value: 3.11
  contexts: [spark-runtime, managed-node, spark-client, spark-image, ansible, devops]

PYSPARK_PYTHON:
  value: python3.11
  contexts: [spark-runtime, spark-client, devops]
```

**Rationale**: `PYTHON_VERSION` is a version number (3.11), while `PYSPARK_PYTHON` is an executable path (python3.11). They serve different purposes and cannot be consolidated.

### Different Semantics

Variables that seem similar but have different meanings should NOT be consolidated.

**Example**:
```yaml
ES_URL:
  value: https://es01:9200
  contexts: [observability]

ES_HOST:
  contexts: [observability, spark-runtime, devops, elastic-agent]
  values:
    observability: es01
    spark-runtime: GaryPC.local
    devops: GaryPC.local
    elastic-agent: GaryPC.local
```

**Rationale**: `ES_URL` is a complete URL, while `ES_HOST` is just the hostname. They serve different purposes.

### 8. No Default Values in Scripts or Deployment Files

**Rule**: Do not assign default values to variables defined in `variables.yaml` when using them in scripts or deployment files (e.g., `docker-compose.yml`). Instead, let the variable be null/empty, which will cause errors more quickly, or add explicit checks that error if the value is null.

**Rationale**: Default values mask configuration errors and can lead to applications running with incorrect settings. By requiring variables to be explicitly set, we ensure that:
- Configuration errors are caught early
- The source of truth (`variables.yaml`) is always used
- Missing variables fail fast rather than silently using incorrect defaults

**Example - Bad** (avoid):
```bash
# In a script
ES_HOST="${ES_HOST:-es01}"  # Don't do this!
ES_PORT="${ES_PORT:-9200}"  # Don't do this!
```

```yaml
# In docker-compose.yml
environment:
  ES_HOST: "${ES_HOST:-es01}"  # Don't do this!
```

**Example - Good**:
```bash
# In a script - check and error if not set
if [[ -z "$ES_HOST" ]]; then
    echo "Error: ES_HOST not set. Source the appropriate environment file." >&2
    exit 1
fi
```

```yaml
# In docker-compose.yml - no default, will error if not set
environment:
  ES_HOST: "${ES_HOST}"  # Will be empty if not set, causing error
```

**Exception**: Variables that are truly optional (not defined in `variables.yaml`) may have defaults, but should be clearly documented as such.

## Validation Checklist

Before committing changes to `variables.yaml`, verify:

- [ ] Each entity has only one variable name (unless there's a compelling reason)
- [ ] Variables with different values in different contexts use `values` dictionary
- [ ] No variable aliasing without extension (variables referencing other variables without adding to them)
- [ ] All contexts in `variables.yaml` are defined in `contexts.yaml`
- [ ] Application-specific variable names are mapped in deployment configs (not duplicated in `variables.yaml`)
- [ ] Variable names follow standardized naming conventions
- [ ] Related variables are grouped together in the file
- [ ] No default values assigned to variables from `variables.yaml` in scripts or deployment files
- [ ] Scripts check for required variables and error if not set

## Related Documents

- `vars/docs/ARCHITECTURE.md` - High-level architecture of the variable context framework
- `vars/docs/IMPLEMENTATION.md` - Detailed implementation and file specifications
- `vars/docs/BEST_PRACTICES.md` - Rationale for the common directory approach
- `vars/README.md` - Module overview and quick reference

