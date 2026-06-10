# Context Variable Best Practices

This document defines the standards and best practices for the variable context framework: how to define context variables in `vars/variables.yaml`, how to specify contexts in `vars/contexts.yaml`, and how playbooks, scripts, and applications consume the generated context files.

## Purpose

The variable context framework provides centralized management of configuration variables across multiple applications and deployment targets. This document gives variable authors and playbook/script authors the rules they **must** follow and the practices they **should** follow so that configuration remains consistent, fail-fast, and maintained in a single place.

## Definitions

- **Context variable**: A variable defined in `vars/variables.yaml` and tagged with one or more contexts. Context variables use `UPPER_SNAKE_CASE` names.
- **Context**: A named output target defined in `vars/contexts.yaml` with a `name`, a `type` (output format), an `output` filename, and a `description`.
- **Generated context file**: A file the generator writes into the flat `vars/contexts/` directory (e.g. `servicenow_ansible_vars.yml`, `spark_client_env.sh`). Generated files are gitignored and carry a "Do not edit manually!" header.
- **Generator**: `vars/generate_contexts.py`, invoked through the bootstrap wrapper `vars/generate_contexts.sh` (system Python, auto-installs PyYAML if missing).
- **Application variable**: A consumer-side name (typically `snake_case`, e.g. `sn_url`, `observability_platform`) that a playbook or role maps from a context variable.
- **Secret variable**: A context variable marked `secret: true` in `variables.yaml`. Its value is resolved at generation time from an environment variable first, then `vars/secrets.yaml`; a secret also marked `required: true` aborts generation when unset.

## Framework Overview

```
vars/
├── variables.yaml           # Source: single source of truth for all context variables
├── contexts.yaml            # Source: context specifications (name, type, output, description)
├── generate_contexts.py     # Generator script
├── generate_contexts.sh     # Bootstrap wrapper (system Python)
├── secrets.yaml             # Local secrets (gitignored); template: secrets.example.yaml
└── contexts/                # Generated files (gitignored) — FLAT, no subdirectories
    ├── observability_docker.env
    ├── spark-configmap.yaml
    ├── spark-image.toml
    ├── spark_ansible_vars.yml
    ├── dynatrace_ansible_vars.yml
    ├── elastic_observability_ansible_vars.yml
    ├── servicenow_ansible_vars.yml
    ├── nfs_ansible_vars.yml
    ├── elastic_agent_ansible_vars.yml
    ├── elastic_agent_env.conf
    ├── spark_client_env.sh
    ├── ispark_client_env.sh
    ├── devops_env.sh
    └── managed_node_env.sh
```

Each entry in `variables.yaml` has:

- `value` (single value) or `values` (per-context dictionary, with an optional `default` key);
- `contexts`: the list of contexts the variable belongs to;
- `section` (optional): a grouping label emitted as a comment header in generated Ansible vars files;
- `secret` / `required` (optional): secret handling flags.

Supported context `type` values: `docker-env`, `shell_env`, `systemd_env`, `toml`, `configmap`, `ansible_vars`. All `output` filenames are written directly under `vars/contexts/` (flat structure).

The generator regenerates a context file only when `variables.yaml`, `contexts.yaml`, or `secrets.yaml` is newer than the output (use `-f` to force). It validates that every context referenced in `variables.yaml` is defined in `contexts.yaml` and warns about undefined contexts.

Ansible playbooks consume the generated files via `vars_files`, for example:

```yaml
# ansible/playbooks/servicenow/cmdb/deploy.yml
vars_files:
  - "{{ playbook_dir | dirname | dirname | dirname | dirname | dirname }}/vars/contexts/servicenow_ansible_vars.yml"
  - "{{ playbook_dir | dirname | dirname | dirname | dirname | dirname }}/vars/contexts/dynatrace_ansible_vars.yml"
```

## Variable Reference Syntax

Variables can reference other variables in their values:

1. **Simple reference (current context)**: `${VAR_NAME}` references `VAR_NAME` in the context of the variable being defined.
2. **Context-specific reference**: `${context:VAR_NAME}` references `VAR_NAME` in the named context, allowing one context to reuse another context's value without adding the referenced variable to its own output.

Expansion is **linear, in definition order**: a variable may only reference variables defined earlier in `variables.yaml`. The generator warns when a reference cannot be expanded.

### Example: simple reference (current context)

```yaml
SPARK_MASTER_HOST:
  contexts: [observability, ispark, spark-client, spark-ansible]
  values:
    observability: Lab3.lan
    spark-client: Lab3.lan

SPARK_MASTER:
  contexts: [spark-runtime, spark-client]
  values:
    spark-runtime: spark://spark-master-0.spark-master-headless.spark.svc.cluster.local:7077
    spark-client: spark://${SPARK_MASTER_HOST}:${SPARK_MASTER_PORT}
```

In the `spark-client` context, `${SPARK_MASTER_HOST}` and `${SPARK_MASTER_PORT}` resolve to that context's values.

### Example: context-specific reference

```yaml
ELASTICSEARCH_HOST:
  contexts: [elastic-agent]
  values:
    elastic-agent: https://${observability:ES_HOST}:${observability:ES_PORT}
```

`ELASTICSEARCH_HOST` in the `elastic-agent` context reuses `ES_HOST` and `ES_PORT` from the `observability` context. This prevents `ES_HOST` and `ES_PORT` from polluting the `elastic-agent` output.

## Variable Definition Syntax

Simple format (one value for all contexts):

```yaml
VAR_NAME:
  section: Optional grouping label
  value: "value"
  contexts: [context1, context2]
```

Context-specific values:

```yaml
VAR_NAME:
  contexts: [context1, context2]
  values:
    context1: "value1"
    context2: "value2"
    default: "default_value"   # optional fallback for contexts without a key
```

## Statements

1. Single source of truth
   1. `vars/variables.yaml` **must** be the single source of truth for context variables. Playbooks **must not** define or override context variable values.
   2. When a playbook needs a new configuration value, the author **must** add it to `vars/variables.yaml` with the appropriate `contexts` list and regenerate the context files; the author **must not** hard-code the value in the playbook.
   3. Consumers **must** load context variables only from the generated context files (`vars/contexts/*`). Consumers **must not** duplicate constant values in script or playbook logic.
   4. `vars/variables.yaml` defines the variable contract and values; playbooks and scripts implement behavior using those values. When multiple consumers need a value, the author **must** add a variable (and contexts) rather than hard-coding the value in one implementation.
2. Fail fast — no defaults over context variables
   1. Playbooks **must not** apply `default(...)` filters (or other fallback values) to context variables. If a context variable is not defined, Ansible **must** fail with an error so the missing variable is fixed in `vars/variables.yaml` rather than silently defaulted. Playbook-internal constants that are not context variables **may** still have inline values.
   2. Scripts **must not** assign shell fallback defaults (e.g. `VAR="${VAR:-/some/default}"`) to variables expected from generated context files. Scripts **must** check required variables and exit with an explicit, actionable error when one is unset.
   3. When a playbook or role maps an application variable from a context variable (e.g. `observability_platform` from `OBSERVABILITY_PLATFORM`), the mapping **must** be a direct reference, assigned once in playbook/role `vars`. Nested or chained defaults such as `observability_platform | default(OBSERVABILITY_PLATFORM | default('elastic'))` **must not** be used.
   4. Variables that are truly optional (not defined in `variables.yaml`) **may** have defaults, but authors **should** document them as optional.
3. Variable design
   1. Each entity (e.g. the Elasticsearch host) **should** have one and only one variable name, unless there is a compelling reason otherwise. Multiple names for the same entity create confusion and order-of-execution issues.
   2. When a variable needs different values in different contexts, the author **must** use the `values` dictionary with context-specific keys rather than creating separate variables (e.g. `LS_HOST_EXTERNAL`).
   3. A variable **may** reference another variable when extending its value (e.g. `ES_CONFIG_DIR: ${ES_DIR}/config`). A variable **must not** be a pure alias of another variable (a reference with no extension); consolidate aliases into one variable.
   4. Authors **should** use context-specific references (`${context:VAR_NAME}`) instead of adding a variable to extra contexts it is not otherwise needed in.
   5. Variables that represent the same concept in different formats (e.g. `PYTHON_VERSION: 3.11` vs `PYSPARK_PYTHON: python3.11`) or with different semantics (e.g. `ES_URL` vs `ES_HOST`) **must not** be consolidated.
   6. Authors **should** use consistent name prefixes for related variables (`ES_*`, `KIBANA_*`, `LS_*`, `SPARK_*`, `OTEL_*`, `SN_*`, `DT_*`).
   7. Every context referenced in `variables.yaml` **must** be defined in `contexts.yaml`. The generator warns about undefined contexts; authors **must** resolve these warnings.
   8. When an application expects a different variable name than the standardized name, the author **must** map the name at the consumer (playbook/role `vars`, `docker-compose.yml` `environment:`), not create a duplicate variable in `variables.yaml`.
   9. A variable **must** be defined as a context variable in `variables.yaml` only when two or more applications or systems consume it. Configuration consumed by a single application **must** live in that application's local variable file (e.g. a `common/*.yml` vars file next to the playbooks), not in `variables.yaml`.
   10. A variable's `contexts` list **must** include only contexts that actually consume the variable. When a consumer is removed, the author **must** remove the now-unused context (and the variable itself when only one consumer remains, per the previous statement).
4. Generated files
   1. Generated files **must** live only in the flat `vars/contexts/` directory and **must not** be committed; the directory is gitignored as a whole.
   2. Authors **must not** edit generated files manually; the generator overwrites them and they carry a "Do not edit manually!" header.
   3. The generator **must not** write context output to multiple locations; deployment tooling maps files from `vars/contexts/` to target locations.
   4. Authors **should not** use symlinks to place generated files; symlinks cause cross-platform (Windows/WSL) and deployment problems.
5. Generator
   1. The generator **must** remain data-driven: it **must not** contain hardcoded special cases for specific variable names. When a consumer needs a distinct output shape, the author **must** add a context (and, if needed, a context `type` with explicit generation semantics) instead.
   2. Secret values **must** be supplied via environment variables or `vars/secrets.yaml`, never committed in `variables.yaml`. A secret marked `required: true` **must** cause generation to fail with an actionable error when unset.
   3. Authors **should** regenerate with `cd vars && ./generate_contexts.sh -f` (or per context, e.g. `./generate_contexts.sh -f service-now`) after editing `variables.yaml`, `contexts.yaml`, or `secrets.yaml`.

## Commentary

### Why no defaults over context variables

Default values mask configuration errors and can lead to systems running with incorrect settings. Requiring variables to be explicitly defined in `variables.yaml` ensures configuration errors surface early, the single source of truth is always used, and missing variables fail fast instead of silently using a stale fallback.

Bad (avoid):

```yaml
# Ansible — never default over a context variable
when: (observability_platform | default(OBSERVABILITY_PLATFORM | default('elastic'))) == 'dynatrace'
```

```bash
# Script
ES_HOST="${ES_HOST:-es01}"   # Don't do this!
```

Good:

```yaml
# Playbook loads vars/contexts/dynatrace_ansible_vars.yml via vars_files,
# derives flags from OBSERVABILITY_PLATFORM (no default), and asserts it is
# defined before use.
when: hostvars['localhost']['observability_dynatrace_enabled'] | bool
```

```bash
if [[ -z "$ES_HOST" ]]; then
    echo "Error: ES_HOST not set. Source the appropriate environment file." >&2
    exit 1
fi
```

### Consolidation patterns

Host variable with per-context values, instead of `*_CLIENT` / `*_EXTERNAL` variants:

```yaml
# Before (avoid)
LS_HOST:
  value: logstash01
  contexts: [observability]
LS_HOST_EXTERNAL:
  value: GaryPC.local
  contexts: [elastic-agent]

# After
LS_HOST:
  contexts: [observability, elastic-agent]
  values:
    observability: logstash01
    elastic-agent: GaryPC.local
```

Eliminating an alias without extension:

```yaml
# Before (avoid)
ES_PORT:
  value: ${ELASTIC_PORT}
  contexts: [devops, observability]
ELASTIC_PORT:
  value: 9200
  contexts: [observability, spark-runtime, devops]

# After
ES_PORT:
  value: 9200
  contexts: [observability, spark-runtime, devops]
```

Application name mapping at the consumer instead of duplicate variables:

```yaml
# docker-compose.yml — map ES_* to the names the application expects
environment:
  ELASTIC_PASSWORD: ${ES_PASSWORD}
  ELASTIC_USER: ${ES_USER}
```

### Why a common flat output directory

Keeping all generated files in one flat `vars/contexts/` directory makes it obvious what is generated versus source, requires only a single `.gitignore` entry, allows `rm -rf vars/contexts/` to clean all generated output, and works for files without identifying extensions. Deployment tooling (Ansible `vars_files`, Docker Compose `--env-file`, kubectl apply) maps the files from this directory to their target locations.

### Variable-context grid

`vars/vars-grid.sh` (wrapping `vars-grid.py`) generates a grid showing which variables appear in which contexts. The grid helps identify variables that appear in many contexts (consolidation candidates), contexts with very few variables (removal candidates), and references to missing context definitions.

## Validation Checklist

Before committing changes to `variables.yaml`, verify:

- [ ] Each entity has only one variable name (unless there is a compelling reason)
- [ ] Variables with different values in different contexts use the `values` dictionary
- [ ] No variable aliasing without extension
- [ ] All contexts referenced in `variables.yaml` are defined in `contexts.yaml` (the generator emits warnings)
- [ ] Application-specific variable names are mapped in consumers, not duplicated in `variables.yaml`
- [ ] Variable names follow the standardized prefix conventions
- [ ] Related variables are grouped together (and `section:` labels are set for Ansible contexts)
- [ ] No `default(...)` filters or shell fallbacks over context variables in playbooks, scripts, or deployment files
- [ ] Application variables map directly from context variables (no nested `default()` chains)
- [ ] Scripts check required variables and error if unset
- [ ] Context files regenerated (`cd vars && ./generate_contexts.sh -f`) and no generated files committed

## References

- `vars/README.md` — module overview and quick reference
- `vars/docs/ARCHITECTURE.md` — high-level architecture of the variable context framework
- `vars/docs/IMPLEMENTATION.md` — detailed implementation and file specifications
- `vars/docs/SECRETS_MANAGEMENT.md` — secret variable handling
- `meta-standards/tpgs-for-tpgs.md` and `meta-standards/keywords-for-standards.md` — requirement keyword conventions used in this document
