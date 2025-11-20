# Variable Context Framework: Best Practices

## Executive Summary

This document describes best practices for using the variable context framework, which provides centralized management of configuration variables across multiple applications and deployment targets.

## Overview

The variable context framework uses a **common directory approach** (`vars/contexts/`) for all generated configuration files. This approach provides:

- ✅ **Single source of truth**: All generated files in one place
- ✅ **Clear separation**: Obvious what's generated vs. source
- ✅ **Simple `.gitignore`**: One directory exclusion
- ✅ **Easy to clean**: `rm -rf vars/contexts/` removes all generated files
- ✅ **Consistent structure**: All contexts follow same pattern
- ✅ **Version control friendly**: Generated files clearly separated
- ✅ **Extension-agnostic**: Works for files without identifying extensions

## Structure

```
vars/
├── variables.yaml          # Source: Single source of truth for all variables
├── contexts.yaml           # Source: Context specifications
├── generate_env.py         # Source: Generator script
└── contexts/               # Generated (gitignored)
    ├── observability/
    │   └── .env
    ├── spark-runtime/
    │   └── spark-configmap.yaml
    └── spark-client/
        └── spark_env.sh
```

## User Reference

### Variable Reference Syntax

Variables can reference other variables using the following syntax:

#### Syntax Forms

1. **Simple Reference** (Current Context):
   ```
   ${VAR_NAME}
   ```
   - References `VAR_NAME` in the **current context** (the context of the variable being defined)
   - Example: `${ES_PORT}` in `elastic-agent-systemd` context references `ES_PORT` in `elastic-agent-systemd` context

2. **Context-Specific Reference**:
   ```
   ${context:VAR_NAME}
   ```
   - References `VAR_NAME` in the **specified context**
   - Allows variables in one context to reference values from another context
   - Example: `${observability:ES_HOST}` references `ES_HOST` from the `observability` context

### Variable Definition Syntax

Variables are defined in `vars/variables.yaml` with the following structure:

#### Simple Format
```yaml
VAR_NAME:
  value: "value"
  contexts: [context1, context2]
```

#### Context-Specific Values
```yaml
VAR_NAME:
  contexts: [context1, context2]
  values:
    context1: "value1"
    context2: "value2"
    default: "default_value"  # Optional fallback
```

### Examples

#### Example 1: Simple Reference (Current Context)
```yaml
ES_PORT:
  value: 9200
  contexts: [observability, elastic-agent-systemd]

ES_HOST:
  contexts: [observability, elastic-agent-systemd]
  values:
    observability: es01
    elastic-agent-systemd: GaryPC.local

ELASTIC_URL:
  contexts: [observability]
  values:
    observability: https://${ES_HOST}:${ES_PORT}
```
In the `observability` context, `${ES_HOST}` and `${ES_PORT}` reference the values from the same context, resulting in `https://es01:9200`.

#### Example 2: Context-Specific Reference
```yaml
ES_HOST:
  contexts: [observability, spark-runtime]
  values:
    observability: es01
    spark-runtime: GaryPC.local

ELASTICSEARCH_HOST:
  contexts: [elastic-agent-systemd]
  values:
    elastic-agent-systemd: https://${observability:ES_HOST}:${observability:ES_PORT}
```
The `ELASTICSEARCH_HOST` variable in `elastic-agent-systemd` context references `ES_HOST` and `ES_PORT` from the `observability` context, resulting in `https://es01:9200`. This prevents `ES_HOST` and `ES_PORT` from appearing in the `elastic-agent-systemd` context output.

#### Example 3: Mixed References
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
In each context, `${ES_DIR}` references the context-specific value of `ES_DIR`, resulting in:
- `devops`: `${HOME}/repos/elastic-on-spark/observability/elasticsearch/config`
- `observability`: `/usr/share/elasticsearch/elasticsearch/config`

#### Example 4: Cross-Context Reference with Context-Specific Values
```yaml
ES_HOST:
  contexts: [observability, spark-runtime]
  values:
    observability: es01
    spark-runtime: GaryPC.local

ES_PORT:
  value: 9200
  contexts: [observability, spark-runtime]

ELASTICSEARCH_USERNAME:
  value: ${observability:ES_USER}
  contexts: [elastic-agent-systemd]

ELASTICSEARCH_PASSWORD:
  value: ${observability:ES_PASSWORD}
  contexts: [elastic-agent-systemd]
```
The `ELASTICSEARCH_*` variables in `elastic-agent-systemd` context reference `ES_USER` and `ES_PASSWORD` from the `observability` context, ensuring consistent values without duplicating variables.

## Best Practices

### ✅ DO

1. **Use common directory for multi-application projects**
   - Provides consistency and clarity
   - Simplifies version control
   - Makes it obvious what's generated
   - Especially important for files without identifying extensions

2. **Keep generated files clearly separated from source**
   - Use dedicated directory (e.g., `vars/contexts/`)
   - Add header comments to generated files
   - Use consistent naming patterns

3. **Use context-specific references to avoid variable pollution**
   - When a variable in one context needs values from another context, use `${context:VAR_NAME}` syntax
   - This prevents unnecessary variables from appearing in contexts where they're not needed

4. **Document deployment process**
   - Explain why files are in common directory
   - Show how deployment maps files from source to target locations
   - Explain source/target structure differences

5. **Use simple `.gitignore` patterns**
   - Ignore entire generated directory
   - Avoid per-file exclusions

6. **Add convenience tooling**
   - Scripts to copy files for local development
   - Validation to detect manual edits
   - Clear error messages if files are missing

### ❌ DON'T

1. **Don't mix generated files with source files**
   - Makes it unclear what's generated
   - Risk of manual edits being overwritten
   - Complex `.gitignore` patterns
   - Especially problematic for files without identifying extensions

2. **Don't use symlinks for cross-platform projects**
   - Windows/WSL compatibility issues
   - Deployment complexity
   - `.gitignore` confusion

3. **Don't generate to multiple locations**
   - Risk of divergence
   - Duplication
   - Maintenance burden

4. **Don't commit generated files**
   - Unless they're build artifacts
   - Keep source of truth in `variables.yaml`

5. **Don't add variables to contexts unnecessarily**
   - Use context-specific references (`${context:VAR_NAME}`) instead
   - This keeps generated files clean and focused

## Conclusion

The common directory approach (`vars/contexts/`) provides clarity and maintainability for managing configuration variables across multiple applications and deployment targets. The context-specific variable reference syntax (`${context:VAR_NAME}`) enables clean separation of concerns while maintaining a single source of truth.

