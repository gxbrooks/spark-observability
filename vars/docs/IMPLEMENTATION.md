# Variable Context Framework: Implementation

## Executive Summary

This document provides detailed implementation information about the variable context framework, including all generated files, their formats, consumers, and deployment processes.

## Generated Files Overview

The framework generates 11 context-specific files from `vars/variables.yaml`. Each file is tailored to its consumption pattern (Docker Compose, Kubernetes, shell scripts, Ansible, etc.).

## Context Details

### 1. Observability Context

**Generated File**: `vars/contexts/observability/.env`  
**Format**: Environment file (`KEY=VALUE`, no export)  
**Purpose**: Docker Compose environment variables for observability stack

**Consumers**:
- **Docker Compose**: Automatically reads `.env` from same directory as `docker-compose.yml`
- **Ansible**: Copies file to `{{ observability_dir }}/.env` during deployment

**Deployment**:
```yaml
# ansible/playbooks/observability/deploy.yml
- name: Copy .env file (Linux)
  copy:
    src: "{{ playbook_dir }}/../../../vars/contexts/observability/.env"
    dest: "{{ observability_dir }}/.env"
    mode: '0644'
```

**Local Development**:
```bash
# Option 1: Use convenience script
./scripts/setup-local-env.sh

# Option 2: Manual copy
cp vars/contexts/observability/.env observability/.env

# Option 3: Use --env-file flag
docker compose --env-file vars/contexts/observability/.env up -d
```

**Variables Included**: `ELASTIC_URL`, `ELASTIC_PASSWORD`, `STACK_VERSION`, `CA_CERT`, etc.

---

### 2. Spark Image Context

**Generated File**: `vars/contexts/spark-image/spark-image.toml`  
**Format**: TOML with `[env]` section  
**Purpose**: Build-time configuration for Spark Docker images

**Consumers**:
- **Docker Build**: Used as build arguments via Ansible playbooks
- **Ansible**: Read by Spark image build playbooks

**Deployment**: Not deployed to managed nodes; used during image build on control node

**Variables Included**: `SPARK_VERSION`, `HADOOP_VERSION`, `SCALA_VERSION`, etc.

---

### 3. Spark Runtime Context

**Generated File**: `vars/contexts/spark-runtime/spark-configmap.yaml`  
**Format**: Kubernetes ConfigMap YAML  
**Purpose**: Environment variables for Spark pods in Kubernetes

**Consumers**:
- **Kubernetes**: Applied as ConfigMap in `spark` namespace
- **Ansible**: Applied via `kubectl apply` during Spark deployment

**Deployment**:
```yaml
# ansible/playbooks/spark/deploy.yml
- name: Register generated ConfigMap for pod env
  slurp:
    src: "{{ project_root }}/vars/contexts/spark-runtime/spark-configmap.yaml"
  register: spark_configmap

- name: Apply generated env ConfigMap for pods
  k8s:
    definition: "{{ (spark_configmap.content | b64decode) | from_yaml }}"
```

**Local Development**:
```bash
kubectl apply -f vars/contexts/spark-runtime/spark-configmap.yaml
```

**Variables Included**: `SPARK_MASTER_URL`, `SPARK_OTEL_LISTENER_JAR`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `ES_URL`, etc.

---

### 4. Ansible Context

**Generated File**: `vars/contexts/ansible/spark_vars.yml`  
**Format**: Ansible variables YAML with structured formatting  
**Purpose**: Variables for Spark Ansible playbooks and roles

**Consumers**:
- **Ansible Playbooks**: Loaded via `vars_files` directive
- **Control Node Only**: Never deployed to managed nodes

**Usage**:
```yaml
# ansible/playbooks/spark/deploy.yml
vars_files:
  - "{{ playbook_dir | dirname | dirname | dirname }}/vars/contexts/ansible/spark_vars.yml"
```

**Variables Included**: `spark_version`, `spark_home`, `spark_events_dir`, `elastic_*` settings, `k8s_namespace`, etc.

---

### 5. NFS Context

**Generated File**: `vars/contexts/nfs/nfs_vars.yml`  
**Format**: Ansible variables YAML  
**Purpose**: Variables for NFS server configuration playbooks

**Consumers**:
- **Ansible Playbooks**: Loaded via `vars_files` directive
- **Control Node Only**: Never deployed to managed nodes

**Usage**:
```yaml
# ansible/playbooks/nfs/install.yml
vars_files:
  - "{{ playbook_dir | dirname | dirname | dirname }}/vars/contexts/nfs/nfs_vars.yml"
```

**Variables Included**: NFS server configuration, mount points, export paths, etc.

---

### 6. Spark Client Context

**Generated File**: `vars/contexts/spark-client/spark_env.sh`  
**Format**: Shell environment file (`export KEY="VALUE"`)  
**Purpose**: Developer environment variables for running Spark applications locally

**Consumers**:
- **Shell Scripts**: Sourced by `.bashrc`
- **Local Development**: Sourced directly by developers
- **Control Node Only**: Never deployed to managed nodes

**Usage**:
```bash
# In .bashrc
source vars/contexts/spark-client/spark_env.sh

# In scripts
source vars/contexts/spark-client/spark_env.sh
```

**Variables Included**: `SPARK_HOME`, `SPARK_MASTER_URL`, `PYSPARK_PYTHON`, `OTEL_EXPORTER_OTLP_ENDPOINT`, etc.

---

### 7. iSpark Context

**Generated File**: `vars/contexts/ispark/ispark_env.sh`  
**Format**: Shell environment file (`export KEY="VALUE"`)  
**Purpose**: Environment variables for interactive Spark (iPython) sessions

**Consumers**:
- **iSpark Launcher**: `spark/ispark/launch_ipython.sh`
- **Local Development**: Sourced for interactive Spark sessions
- **Control Node Only**: Never deployed to managed nodes

**Usage**:
```bash
# spark/ispark/launch_ipython.sh
source vars/contexts/ispark/ispark_env.sh
```

**Variables Included**: `SPARK_HOME`, `PYSPARK_DRIVER_PYTHON`, `PYSPARK_PYTHON`, etc.

---

### 8. Elastic Agent Context (DEPRECATED/UNUSED)

**Generated File**: `vars/contexts/elastic-agent/elastic_agent_env.sh`  
**Format**: Shell environment file (`export KEY="VALUE"`)  
**Purpose**: ~~Host-level environment variables for Elastic Agent (reference only)~~ **NOT USED**

**Status**: This context is **not used** by any playbooks or scripts. The actual deployment uses the `elastic-agent-systemd` context instead.

**Note**: The actual file deployed to managed nodes is generated via `elastic-agent-systemd` context.

**Variables Included**: `ELASTIC_URL`, `CA_CERT`, etc. (same variables as `elastic-agent-systemd` but in shell format)

---

### 8a. Elastic Agent Systemd Context

**Generated File**: `elastic-agent/elastic_agent_env_systemd.conf`  
**Format**: Systemd EnvironmentFile format (`Environment="KEY=VALUE"`)  
**Purpose**: Systemd environment file for Elastic Agent service on Linux hosts

**Consumers**:
- **Systemd Service**: Referenced in Elastic Agent systemd service file via `EnvironmentFile=` directive
- **Deployed to**: `/etc/elastic-agent/elastic_agent_env.conf` on managed nodes via Ansible

**Variables Included**: 
- **Canonical Elastic Agent variables** (preferred): `ELASTICSEARCH_HOST`, `ELASTICSEARCH_USERNAME`, `ELASTICSEARCH_PASSWORD`, `ELASTICSEARCH_CA`, `ELASTICSEARCH_INSECURE`
- **Other variables**: `LS_HOST`, `LS_SPARK_EVENTS_PORT`, `KUBERNETES_API_SERVER`, `SPARK_EVENTS_DIR`, `CA_CERT`
- **Legacy variables** (for backward compatibility): `ES_*`, `ELASTIC_*`

---

### 9. Elastic Agent Ansible Context

**Generated File**: `vars/contexts/elastic-agent-ansible/elastic_agent_vars.yml`  
**Format**: Ansible variables YAML  
**Purpose**: Variables for Elastic Agent deployment playbooks

**Consumers**:
- **Ansible Playbooks**: Loaded via `vars_files` directive
- **Control Node Only**: Never deployed to managed nodes

**Usage**:
```yaml
# ansible/playbooks/elastic-agent/install.yml
vars_files:
  - "{{ playbook_dir | dirname | dirname | dirname }}/vars/contexts/elastic-agent-ansible/elastic_agent_vars.yml"
```

**Variables Included**: `elastic_agent_version`, `elastic_agent_url`, `elastic_agent_install_dir`, etc.

---

### 10. DevOps Context

**Generated File**: `vars/contexts/devops/devops_env.sh`  
**Format**: Shell environment file (`export KEY="VALUE"`)  
**Purpose**: Environment variables for devops client initialization (Python, Java versions, OTEL config)

**Consumers**:
- **`.bashrc`**: Sourced on login
- **Shell Scripts**: `linux/spark-submit-client.sh`, `linux/generate_spark_defaults.sh`
- **Local Development**: Sourced for devops tooling
- **Control Node Only**: Never deployed to managed nodes

**Usage**:
```bash
# In .bashrc
source vars/contexts/devops/devops_env.sh

# In scripts
source vars/contexts/devops/devops_env.sh
```

**Variables Included**: `PYTHON_VERSION`, `JAVA_HOME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `ES_URL`, `ES_USER`, `ES_PASSWORD`, etc.

---

### 11. Managed Node Context

**Generated File**: `vars/contexts/managed-node/managed_node_env.sh`  
**Format**: Shell environment file (`export KEY="VALUE"`)  
**Purpose**: Environment variables for managed node initialization (Python, Java versions)

**Consumers**:
- **Validation Scripts**: `linux/assert_managed_node.sh`
- **Control Node Only**: Never deployed to managed nodes (used for validation)

**Usage**:
```bash
# linux/assert_managed_node.sh
source vars/contexts/managed-node/managed_node_env.sh
```

**Variables Included**: `PYTHON_VERSION`, `JAVA_HOME`, etc.

---

## Deployment Summary

### Files Deployed to Managed Nodes

| File | Target | Method | Location |
|------|--------|--------|----------|
| `observability/.env` | Observability node | Ansible `copy` | `{{ observability_dir }}/.env` |
| `spark-runtime/spark-configmap.yaml` | Kubernetes cluster | `kubectl apply` | `spark` namespace |

### Files NOT Deployed (Control Node Only)

| File | Usage |
|------|-------|
| `spark-image/spark-image.toml` | Docker build on control node |
| `ansible/*.yml` | Ansible `vars_files` on control node |
| `nfs/nfs_vars.yml` | Ansible `vars_files` on control node |
| `spark-client/*.sh` | Sourced by local scripts |
| `ispark/*.sh` | Sourced by iSpark launcher |
| `elastic-agent/*.sh` | Reference for systemd service |
| `elastic-agent-ansible/*.yml` | Ansible `vars_files` on control node |
| `devops/*.sh` | Sourced by `.bashrc` and scripts |
| `managed-node/*.sh` | Used for validation on control node |

## File Format Details

### Environment File (`.env`)
```bash
# This file is automatically generated from vars/variables.yaml by vars/generate_contexts.py
# Do not edit manually!

KEY1=value1
KEY2=value2
```

### Shell Environment (`.sh`)
```bash
# This file is automatically generated from vars/variables.yaml by vars/generate_contexts.py
# Do not edit manually!

export KEY1="value1"
export KEY2="value2"
```

### TOML (`.toml`)
```toml
# This file is automatically generated from vars/variables.yaml by vars/generate_contexts.py
# Do not edit manually!

[env]
KEY1 = "value1"
KEY2 = "value2"
```

### Kubernetes ConfigMap (`.yaml`)
```yaml
# This file is automatically generated from vars/variables.yaml by vars/generate_contexts.py
# Do not edit manually!

apiVersion: v1
kind: ConfigMap
metadata:
  name: spark-configmap
  namespace: spark
data:
  KEY1: "value1"
  KEY2: "value2"
```

### Ansible Variables (`.yml`)
```yaml
# Centralized variables for Ansible playbooks and roles
# This file is automatically generated from vars/variables.yaml by vars/generate_contexts.py
# Do not edit manually!

spark_version: "3.5.0"
spark_home: "/opt/spark"
elastic_url: "https://es01:9200"
```

## Generation Process

### Step 1: Load Configuration
```python
variables = load_variables()  # From variables.yaml
contexts = load_contexts()    # From contexts.yaml
```

### Step 2: Filter Variables by Context
For each context, filter variables where the context appears in the `contexts` list:
```python
context_vars = {k: v for k, v in variables.items() 
                if context_name in v.get('contexts', [])}
```

### Step 3: Apply Context-Specific Overrides
If a variable has `values` with context-specific overrides, use those:
```python
if 'values' in variable:
    value = variable['values'].get(context_name, variable['values'].get('default'))
else:
    value = variable['value']
```

### Step 4: Generate File
Use appropriate writer function based on context type:
- `write_env()` for `env` type
- `write_shell_env()` for `shell_env` type
- `write_toml()` for `toml` type
- `write_configmap()` for `configmap` type
- `write_ansible_vars()` for `ansible_vars` type

### Step 5: Write to Target
Write generated content to `vars/contexts/<context>/<file>`

## Idempotency

The generator is idempotent:
- Only regenerates files if source files (`variables.yaml`, `contexts.yaml`) are newer
- Uses file modification time comparison
- Can be forced with `-f` flag

## Validation

The generator validates:
- All required variables are present for each context
- Context specifications are valid
- Output paths are writable
- Fails fast with clear error messages

## Related Documents

- `vars/docs/BEST_PRACTICES.md` - Rationale for the approach
- `vars/docs/ARCHITECTURE.md` - High-level architecture
- `vars/README.md` - Module overview and quick reference

