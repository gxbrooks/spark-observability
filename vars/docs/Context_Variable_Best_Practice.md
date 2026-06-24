---
title: Context Variable Technical Policy and Guidelines
---

# Context Variable Technical Policy and Guidelines

This document defines how authors define, generate, and consume **context variables** in a multi-application configuration framework. It applies to any repository that uses a `variables.yaml` source file, a `contexts.yaml` context registry, and generated context output files consumed by playbooks, scripts, and applications.

## Purpose

The context variable framework centralizes configuration that **multiple** applications or deployment targets share. This policy gives variable authors and consumer authors the rules they **must** follow and the practices they **should** follow so configuration remains consistent, fail-fast, and maintained in a single place.

Audiences: engineers who edit `variables.yaml` or `contexts.yaml`, authors of playbooks and scripts that load generated context files, and maintainers of the context generator.

## Definitions

- **Context variable**: A variable defined in `variables.yaml` and tagged with one or more contexts. Context variables use `UPPER_SNAKE_CASE` names.
- **Context**: A named output target defined in `contexts.yaml` with a `name`, a `type` (output format), an `output` filename, and a `description`.
- **Singleton context**: A context that appears in the `contexts` list of **exactly one** context variable in `variables.yaml`. When counting, treat each variable once regardless of how many keys in a `values` dictionary reference that context.
- **Generated context file**: A file the generator writes into the flat `contexts/` directory (for example `servicenow_ansible_vars.yml`, `spark_client_env.sh`). Generated files are gitignored and carry a "Do not edit manually!" header.
- **Generator**: The script that reads `variables.yaml` and `contexts.yaml` and writes context output (for example `generate_contexts.py` invoked via a bootstrap wrapper).
- **Application variable**: A consumer-side name (typically `snake_case`, for example `sn_url`, `observability_platform`) that a playbook or role maps from a context variable.
- **Application-local variable**: Configuration defined in a file colocated with the consuming application (for example `common/vars.yml` next to playbooks, or `servicenow/csdm.yaml` in an application playbook tree), not in `variables.yaml`.
- **Secret variable**: A context variable marked `secret: true` in `variables.yaml`. Its value is resolved at generation time from an environment variable first, then a local secrets file; a secret also marked `required: true` aborts generation when unset.

## Roles and Responsibilities

- **Variable author**: Defines and maintains entries in `variables.yaml` and `contexts.yaml`, regenerates context files, and resolves generator warnings.
- **Consumer author**: Loads generated context files in playbooks, scripts, or deployment manifests; maps application variables from context variables; does not duplicate or override context variable values.
- **Generator maintainer**: Keeps the generator data-driven (no hardcoded variable-name special cases), validates context references, and documents supported context `type` values.

## Statements

1. Single source of truth
   1. `variables.yaml` **must** be the single source of truth for context variables. Consumers **must not** define or override context variable values.
   2. When a playbook needs a new configuration value shared by two or more applications or systems, the author **must** add it to `variables.yaml` with the appropriate `contexts` list and regenerate context files; the author **must not** hard-code the value in the playbook.
   3. Consumers **must** load context variables only from generated context files. Consumers **must not** duplicate constant values in script or playbook logic.
   4. `variables.yaml` defines the variable contract and values; playbooks and scripts implement behavior using those values.
2. Singleton contexts
   1. Authors **should not** assign a variable to a singleton context. Configuration consumed by only one application **should** live in an application-local variable file instead of `variables.yaml`.
   2. When a variable's only remaining consumer is removed, the author **should** move its value to application-local configuration and remove the variable from `variables.yaml`; if the context becomes unused, the author **should** remove the context from `contexts.yaml`.
3. Fail fast — no defaults over context variables
   1. Playbooks **must not** apply `default(...)` filters (or other fallback values) to context variables. If a context variable is not defined, Ansible **must** fail with an error so the missing variable is fixed in `variables.yaml` rather than silently defaulted. Playbook-internal constants that are not context variables **may** still have inline values.
   2. Scripts **must not** assign shell fallback defaults (for example `VAR="${VAR:-/some/default}"`) to variables expected from generated context files. Scripts **must** check required variables and exit with an explicit, actionable error when one is unset.
   3. When a playbook or role maps an application variable from a context variable, the mapping **must** be a direct reference, assigned once in playbook or role `vars`. Nested or chained defaults **must not** be used.
   4. Variables that are truly optional (not defined in `variables.yaml`) **may** have defaults; authors **should** document them as optional.
4. Variable design
   1. Each entity **should** have one and only one variable name, unless there is a compelling reason otherwise.
   2. When a variable needs different values in different contexts, the author **must** use the `values` dictionary with context-specific keys rather than creating separate variables.
   3. A variable **may** reference another variable when extending its value (for example `ES_CONFIG_DIR: ${ES_DIR}/config`). A variable **must not** be a pure alias of another variable; consolidate aliases into one variable.
   4. Authors **should** use context-specific references (`${context:VAR_NAME}`) instead of adding a variable to extra contexts it is not otherwise needed in.
   5. Variables that represent the same concept in different formats or with different semantics **must not** be consolidated.
   6. Authors **should** use consistent name prefixes for related variables.
   7. Every context referenced in `variables.yaml` **must** be defined in `contexts.yaml`. The generator warns about undefined contexts; authors **must** resolve these warnings.
   8. When an application expects a different variable name than the standardized name, the author **must** map the name at the consumer, not create a duplicate variable in `variables.yaml`.
   9. A variable **must** be defined as a context variable in `variables.yaml` only when two or more applications or systems consume it.
   10. A variable's `contexts` list **must** include only contexts that actually consume the variable. When a consumer is removed, the author **must** remove the now-unused context (and the variable itself when only one consumer remains, per statement 2.1).
5. Generated files
   1. Generated files **must** live only in the flat `contexts/` directory and **must not** be committed; the directory is gitignored as a whole.
   2. Authors **must not** edit generated files manually; the generator overwrites them.
   3. The generator **must not** write context output to multiple locations; deployment tooling maps files from `contexts/` to target locations.
   4. Authors **should not** use symlinks to place generated files; symlinks cause cross-platform and deployment problems.
6. Generator
   1. The generator **must** remain data-driven: it **must not** contain hardcoded special cases for specific variable names. When a consumer needs a distinct output shape, the author **must** add a context (and, if needed, a context `type` with explicit generation semantics) instead.
   2. Secret values **must** be supplied via environment variables or a local secrets file, never committed in `variables.yaml`. A secret marked `required: true` **must** cause generation to fail with an actionable error when unset.
   3. Authors **should** regenerate context files after editing `variables.yaml`, `contexts.yaml`, or the secrets file.

## Commentary

### Why singleton contexts should be avoided

A context exists to filter variables into a shared output file for **multiple** consumers. When only one variable references a context, that context is not acting as a shared filter—it is overhead that suggests the value belongs in application-local configuration instead. Keeping single-consumer values out of `variables.yaml` reduces noise, avoids false coupling between unrelated applications, and makes future extraction of the `vars/` module into its own repository easier.

Authors **may** temporarily assign a variable to a singleton context during migration, but **should** move the value to application-local configuration and remove the unused context promptly.

### Why no defaults over context variables

Default values mask configuration errors and can lead to systems running with incorrect settings. Requiring variables to be explicitly defined in `variables.yaml` ensures configuration errors surface early and missing variables fail fast instead of silently using a stale fallback.

### Variable reference syntax

Variables can reference other variables in their values:

1. **Simple reference (current context)**: `${VAR_NAME}` references `VAR_NAME` in the context of the variable being defined.
2. **Context-specific reference**: `${context:VAR_NAME}` references `VAR_NAME` in the named context.

Expansion is linear, in definition order: a variable may only reference variables defined earlier in `variables.yaml`.

### Validation checklist

Before committing changes to `variables.yaml`, verify:

- Each entity has only one variable name (unless there is a compelling reason)
- No variable is assigned solely to a singleton context (move to application-local configuration)
- Variables with different values in different contexts use the `values` dictionary
- No variable aliasing without extension
- All contexts referenced in `variables.yaml` are defined in `contexts.yaml`
- Application-specific variable names are mapped in consumers, not duplicated in `variables.yaml`
- No `default(...)` filters or shell fallbacks over context variables
- Context files regenerated and no generated files committed

## References

- `meta-standards/tpgs-for-tpgs.md` — structure and requirement keywords for TPG documents
- `meta-standards/keywords-for-standards.md` — interpretation of must, should, may, and related keywords
- Repository `vars/README.md` — module overview and project-specific context notes (when present)
- Repository `vars/docs/ARCHITECTURE.md` — high-level architecture of the variable context framework (when present)
- Repository `vars/docs/IMPLEMENTATION.md` — generator and file format details (when present)
