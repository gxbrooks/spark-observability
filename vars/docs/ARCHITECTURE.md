# Variable Context Framework: Architecture

## Executive Summary

This document describes the high-level architecture of the variable context framework, which provides centralized management of configuration variables across multiple applications and deployment targets.

## Architecture Overview

The variable context framework operates on a **two-stage generation process**:

1. **Variable Definition**: All variables are defined in `vars/variables.yaml` along with the contexts (e.g., `observability`, `spark-client`, `ansible`) in which they are relevant.
2. **Context Specification**: `vars/contexts.yaml` defines the output files to be generated for each context, specifying the output format (e.g., `.env`, `shell_env`, `toml`, `configmap`, `ansible_vars`) and the target file path.
3. **Generation**: `vars/generate_contexts.sh` (bootstrap wrapper) uses system Python to call `vars/generate_contexts.py`, which reads `vars/variables.yaml` and `vars/contexts.yaml` to produce context-specific configuration files in `vars/contexts/<context>/`.

**Modular Design**: The `vars/` module is **independent** and uses **system Python** (not project venv) to break circular dependencies. This allows environment files to be generated before Python version is determined or virtual environment exists.

## Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Source Files (Version Controlled)                           │
│                                                             │
│  vars/                                                      │
│  ├── variables.yaml          # Single source of truth       │
│  ├── contexts.yaml            # Context specifications      │
│  ├── generate_contexts.sh     # Wrapper (system Python)     │
│  ├── generate_contexts.py     # Core generator script       │
│  └── README.md                # Module documentation        │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ reads
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Generation Process (Modular, Layered Architecture)          │
│                                                             │
│  Layer 1: generate_contexts.sh (Bootstrap Wrapper)          │
│  ├── Uses system Python (breaks circular dependencies)      │
│  ├── Auto-installs PyYAML if missing                        │
│  └── Calls generate_contexts.py                             │
│                                                             │
│  Layer 2: generate_contexts.py (Core Generator)             │
│  ├── Load variables.yaml                                    │
│  ├── Load contexts.yaml                                     │
│  ├── Filter variables by context                            │
│  └── Generate context-specific files                        │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ writes
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Generated Files (Gitignored)                                │
│                                                             │
│  vars/contexts/                                             │
│  ├── observability_docker.env                               │
│  ├── spark-configmap.yaml                                   │
│  ├── spark_client_env.sh                                    │
│  ├── devops_env.sh                                          │
│  └── ... (other contexts)                                   │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ consumed by
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ Consumers                                                   │
│                                                             │
│  ├── Ansible Playbooks        (vars_files, copy tasks)      │
│  ├── Docker Compose           (--env-file, copied .env)     │
│  ├── Shell Scripts            (source *.sh)                 │
│  ├── Kubernetes               (kubectl apply ConfigMap)     │
│  └── Local Development        (direct sourcing)             │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

### 1. Variable Definition (`variables.yaml`)

Variables are defined with:
- **Value(s)**: Single value or context-specific overrides
- **Contexts**: List of contexts where the variable is used
- **Description**: Optional documentation

Example:
```yaml
ELASTIC_URL:
  value: "https://es01:9200"
  contexts:
    - observability
    - spark-client
    - devops
  description: "Elasticsearch URL"
```

### 2. Context Specification (`contexts.yaml`)

Contexts define:
- **Name**: Unique context identifier
- **Type**: Output format (env, shell_env, toml, configmap, ansible_vars)
- **Output**: Target file path relative to repo root
- **Description**: Purpose of the context

Example:
```yaml
contexts:
  - name: observability
    type: docker-env
    output: observability_docker.env
    description: "Docker Compose environment variables"
```

### 3. Generation Process

The generator:
1. Loads `variables.yaml` and `contexts.yaml`
2. For each context:
   - Filters variables applicable to that context
   - Applies context-specific value overrides if present
   - Generates file using appropriate writer function
   - Writes to `vars/contexts/<context>/<file>`

### 4. Consumption

Generated files are consumed by:
- **Ansible**: Via `vars_files` directive or `copy` tasks
- **Docker Compose**: Via `--env-file` or copied `.env` file
- **Shell Scripts**: Via `source` command
- **Kubernetes**: Via `kubectl apply` for ConfigMaps
- **Local Development**: Direct sourcing or copying

## Directory Structure

```
vars/
├── variables.yaml              # Source: Variable definitions
├── contexts.yaml               # Source: Context specifications
├── generate_contexts.sh        # Source: Bootstrap wrapper
├── generate_contexts.py        # Source: Core generator script
├── README.md                   # Source: Module overview
└── contexts/                   # Generated: All context files (gitignored)
    ├── devops_env.sh
    ├── elastic_agent_ansible_vars.yml
    ├── elastic_agent_env.conf
    ├── ispark_client_env.sh
    ├── managed_node_env.sh
    ├── nfs_ansible_vars.yml
    ├── observability_docker.env
    ├── spark_ansible_vars.yml
    ├── spark_client_env.sh
    ├── spark-configmap.yaml
    ├── spark-image.toml
```


## Context Types

### Environment Files (`.env`)
- **Format**: `KEY=VALUE` (no export)
- **Use Case**: Docker Compose environment variables
- **Example**: `vars/contexts/observability_docker.env`

### Shell Environment (`.sh`)
- **Format**: `export KEY="VALUE"`
- **Use Case**: Shell scripts, `.bashrc`, local development
- **Example**: `vars/contexts/devops_env.sh`

### YAML Files (`.yml`)
- **Format**: YAML structure (Ansible vars, Kubernetes ConfigMaps)
- **Use Case**: Ansible playbooks, Kubernetes resources
- **Example**: `vars/contexts/spark_ansible_vars.yml`

### TOML Files (`.toml`)
- **Format**: TOML key-value pairs
- **Use Case**: Docker build arguments
- **Example**: `vars/contexts/spark-image.toml`

## Deployment Architecture

### Source Environment (DevOps)

```
vars/contexts/                  # Generated files (flat structure)
├── observability_docker.env
├── spark-configmap.yaml
└── ...
```

### Target Environments

Files are mapped from source structure to target locations:

1. **Observability Node**: `.env` → `{{ observability_dir }}/.env`
2. **Kubernetes Cluster**: ConfigMap → Applied via `kubectl`
3. **Local Development**: Direct sourcing from `vars/contexts/`

### Deployment Flow

```
Source (vars/contexts/) → Ansible Playbooks → Target Locations
```

- **Ansible** handles the mapping from source structure to target structure
- **Local development** uses files directly from `vars/contexts/`
- **Kubernetes** receives ConfigMaps via `kubectl apply`

## Key Design Principles

1. **Single Source of Truth**: All variables defined in `variables.yaml`
2. **Context-Based Generation**: Variables filtered and formatted per context
3. **Clear Separation**: Generated files in dedicated directory
4. **Idempotent Generation**: Generator only updates changed files
5. **Fail-Fast Validation**: Missing variables cause immediate failure
6. **Extension-Agnostic**: Works for files without identifying extensions

## Version Control Strategy

- **Source files** (`variables.yaml`, `contexts.yaml`, `generate_contexts.sh`, `generate_contexts.py`): ✅ Committed
- **Generated files** (`vars/contexts/`): ❌ Gitignored
- **`.gitignore` pattern**: `vars/contexts/`

This ensures:
- Source of truth is version controlled
- Generated files are never committed
- Simple, maintainable `.gitignore` pattern

## Related Documents

- `vars/docs/BEST_PRACTICES.md` - Rationale for the approach
- `vars/docs/IMPLEMENTATION.md` - Detailed implementation and file specifications
- `vars/README.md` - Module overview and quick reference

