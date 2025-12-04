# Variable Context Framework

This directory (`vars/`) contains the core components of the project's data-driven variable management framework. It serves as the single source of truth for all configuration variables used across the Spark and Observability stacks.

## Modular, Layered Architecture

The `vars/` module is designed as a **standalone, independent module** that can operate without dependencies on the rest of the project:

### **Layer 1: Bootstrap (System Python)**
- **`generate_env.sh`** - Wrapper script that uses system Python (any 3.x)
- **Purpose**: Breaks circular dependencies by using system Python instead of project venv
- **Dependencies**: Only requires system `python3` and `pyyaml` (auto-installs if missing)
- **Can run**: Before any virtual environment exists, before Python version is determined

### **Layer 2: Core Generator (Python Script)**
- **`generate_env.py`** - Main generator script
- **Purpose**: Transforms `variables.yaml` + `contexts.yaml` into context-specific files
- **Dependencies**: Python 3.x with PyYAML
- **Called by**: `generate_env.sh` wrapper or directly (if PyYAML is installed)

### **Layer 3: Configuration (YAML)**
- **`variables.yaml`** - Single source of truth for all variable values
- **`contexts.yaml`** - Specification of output formats and file paths
- **Purpose**: Declarative configuration, no code dependencies

### **Layer 4: Generated Output**
- **`contexts/`** directory - All generated files (gitignored)
- **Purpose**: Context-specific configuration files consumed by deployment tools

**Key Design Principle**: The `vars/` module is **independent** and uses **system Python** to avoid circular dependencies. This allows environment files to be generated even when:
- No virtual environment exists
- Python version is not yet determined
- Project dependencies are not installed

## Organization

```
vars/
├── README.md                # This file - module overview
├── variables.yaml           # Single source of truth for all variables
├── contexts.yaml            # Context specifications (output formats and paths)
├── generate_env.sh          # Bootstrap wrapper (uses system Python)
├── generate_env.py          # Core generator script
└── contexts/                # Generated files (gitignored)
    ├── observability/
    ├── spark-runtime/
    ├── spark-client/
    └── ... (other contexts)
```

## Quick Start

```bash
# Generate all contexts (recommended - uses wrapper)
bash vars/generate_env.sh

# Force regeneration of specific contexts
bash vars/generate_env.sh -f observability spark-runtime

# Verbose mode
bash vars/generate_env.sh -v devops

# Or directly (requires PyYAML installed)
python3 vars/generate_env.py -f observability spark-runtime
```

## Documentation

- **[BEST_PRACTICES.md](docs/BEST_PRACTICES.md)** - Rationale for the common directory approach and comparison with alternatives
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - High-level architecture, data flow, and component design
- **[IMPLEMENTATION.md](docs/IMPLEMENTATION.md)** - Detailed implementation: all generated files, formats, consumers, and deployment processes

## Contexts

| Context | Output File | Purpose |
|---------|-------------|---------|
| `observability` | `.env` | Docker Compose environment variables |
| `spark-image` | `spark-image.toml` | Spark Docker image build arguments |
| `spark-runtime` | `spark-configmap.yaml` | Kubernetes ConfigMap for Spark pods |
| `ansible` | `spark_vars.yml` | Ansible variables for Spark playbooks |
| `nfs` | `nfs_vars.yml` | Ansible variables for NFS playbooks |
| `spark-client` | `spark_env.sh` | Local Spark client environment |
| `ispark` | `ispark_env.sh` | Interactive Spark (iPython) environment |
| `elastic-agent` | `elastic_agent_env.sh` | Elastic Agent environment (reference only, unused) |
| `elastic-agent-ansible` | `elastic_agent_vars.yml` | Ansible variables for Elastic Agent |
| `devops` | `devops_env.sh` | DevOps client tooling environment |
| `managed-node` | `managed_node_env.sh` | Managed node validation environment |

## Common Workflow

1. Edit `vars/variables.yaml` to add or update values
2. Tag variables with relevant contexts
3. Run `bash vars/generate_env.sh -f <context>` to regenerate (recommended)
   - Or: `python3 vars/generate_env.py -f <context>` (if PyYAML installed)
4. Commit `vars/variables.yaml` (generated files remain gitignored)

## Key Principles

- **Single Source of Truth**: All variables defined in `variables.yaml`
- **Context-Based Generation**: Variables filtered and formatted per context
- **Clear Separation**: Generated files in dedicated `contexts/` directory
- **Idempotent**: Generator only updates changed files
- **Fail-Fast**: Missing variables cause immediate failure
- **Modular Independence**: `vars/` module uses system Python, no project dependencies
- **Circular Dependency Resolution**: Wrapper script breaks dependency chain

## Version Control

- ✅ **Source files** (`variables.yaml`, `contexts.yaml`, `generate_env.py`, `generate_env.sh`): Committed
- ❌ **Generated files** (`contexts/`): Gitignored

## See Also

- `vars/docs/BEST_PRACTICES.md` - Rationale and best practices
- `vars/docs/ARCHITECTURE.md` - High-level architecture
- `vars/docs/IMPLEMENTATION.md` - Detailed implementation
- `scripts/setup-local-env.sh` - Convenience script for local development
