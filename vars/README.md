# Variable Context Framework

This directory (`vars/`) contains the core components of the project's data-driven variable management framework. It serves as the single source of truth for all configuration variables used across the Spark and Observability stacks.

## Organization

```
vars/
├── README.md                # This file - module overview
├── variables.yaml           # Single source of truth for all variables
├── contexts.yaml            # Context specifications (output formats and paths)
├── generate_env.py          # Generator script
└── contexts/                # Generated files (gitignored)
    ├── observability/
    ├── spark-runtime/
    ├── spark-client/
    └── ... (other contexts)
```

## Quick Start

```bash
# Generate all contexts
python3 vars/generate_env.py

# Force regeneration of specific contexts
python3 vars/generate_env.py -f observability spark-runtime

# Verbose mode
python3 vars/generate_env.py -v devops
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
3. Run `python3 vars/generate_env.py -f <context>` to regenerate
4. Commit `vars/variables.yaml` (generated files remain gitignored)

## Key Principles

- **Single Source of Truth**: All variables defined in `variables.yaml`
- **Context-Based Generation**: Variables filtered and formatted per context
- **Clear Separation**: Generated files in dedicated `contexts/` directory
- **Idempotent**: Generator only updates changed files
- **Fail-Fast**: Missing variables cause immediate failure

## Version Control

- ✅ **Source files** (`variables.yaml`, `contexts.yaml`, `generate_env.py`): Committed
- ❌ **Generated files** (`contexts/`): Gitignored

## See Also

- `vars/docs/BEST_PRACTICES.md` - Rationale and best practices
- `vars/docs/ARCHITECTURE.md` - High-level architecture
- `vars/docs/IMPLEMENTATION.md` - Detailed implementation
- `scripts/setup-local-env.sh` - Convenience script for local development
