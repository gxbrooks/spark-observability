# Variable Context Framework: Best Practices

## Executive Summary

This document rationalizes the approach taken for the variable context framework, comparing **common directory** (`vars/contexts/`) vs. **module-specific directories** and explaining why the common directory approach is the best choice for this project.

## Scope: Variable-Based Configuration Files

This document applies specifically to **variable-based configuration files** generated from `vars/variables.yaml` via `vars/generate_env.py`:

- **Environment files**: `.env`, `.sh` (shell environment)
- **Configuration files**: `.yml` (YAML configs), `.toml` (TOML configs)
- **Kubernetes manifests**: ConfigMaps, variable files

**Not in scope**:
- Build artifacts (`.jar`, `.class`, `.so`, `.exe`) - recognized by extension
- Compiled code - handled by build systems (Maven, Gradle, etc.)
- Generated source code - typically in `target/`, `build/`, `dist/`

Variable-based configuration files don't have a specific extension that identifies them as generated, making explicit segregation in a dedicated directory more useful for clarity and version control.

## Industry Best Practices

### 1. **Separation of Concerns** (Configuration vs. Code)
- ✅ **Configuration should be separate from application code**
- ✅ **Generated files should be clearly identifiable**
- ✅ **Single source of truth for all configuration**

### 2. **Version Control Strategy**
- ✅ **Generated files should NOT be committed** (unless they're build artifacts)
- ✅ **Source files (templates, generators) SHOULD be committed**
- ✅ **Clear `.gitignore` patterns**

### 3. **Deployment and Distribution**
- ✅ **Files must be in the right location on target environments**
- ✅ **Support both local development and production deployment**
- ✅ **Deployment tools handle file placement**

## Approach Comparison

### Common Directory (`vars/contexts/`) ✅ **SELECTED**

**Structure**:
```
vars/
├── variables.yaml          # Source
├── contexts.yaml           # Source
├── generate_env.py         # Source
└── contexts/               # Generated (gitignored)
    ├── observability/
    │   └── .env
    ├── spark-runtime/
    │   └── spark-configmap.yaml
    └── spark-client/
        └── spark_env.sh
```

**Pros**:
- ✅ **Single source of truth**: All generated files in one place
- ✅ **Clear separation**: Obvious what's generated vs. source
- ✅ **Simple `.gitignore`**: One directory exclusion
- ✅ **Easy to clean**: `rm -rf vars/contexts/` removes all generated files
- ✅ **Consistent structure**: All contexts follow same pattern
- ✅ **Version control friendly**: Generated files clearly separated
- ✅ **Extension-agnostic**: Works for files without identifying extensions

**Cons**:
- ⚠️ **Source and target directory structures differ**: The DevOps (source) environment structure doesn't directly map to target environment structures. Files must be copied/mapped from `vars/contexts/` to their required locations on target systems, requiring deployment tooling to understand the mapping.

### Module-Specific Directories ❌ **REJECTED**

**Structure**:
```
observability/
├── docker-compose.yml       # Source
└── .env                     # Generated (gitignored)

spark/
├── conf/
│   └── spark-defaults.conf  # Generated (gitignored)
└── k8s/
    └── spark-configmap.yaml # Generated (gitignored)
```

**Cons**:
- ❌ **Scattered generated files**: Hard to identify what's generated
- ❌ **Complex `.gitignore`**: Must exclude files in multiple locations
- ❌ **Risk of manual edits**: Generated files look like source files
- ❌ **Harder to clean**: Must know all locations to remove generated files
- ❌ **Inconsistent structure**: Each module has different patterns
- ❌ **Version control confusion**: Generated files mixed with source files
- ❌ **Extension-agnostic issue**: Without identifying extensions, harder to distinguish generated from source

## Decision Rationale

### Project Characteristics

1. **Multi-application**: Spark, Observability, Elastic Agent, NFS
2. **Multiple deployment targets**: Kubernetes, Docker Compose, systemd
3. **Complex deployment**: Ansible playbooks with file copying/mapping
4. **Multiple generated file types**: `.env`, `.yml`, `.sh`, `.toml` (no identifying extensions)
5. **Source/target structure mismatch**: DevOps environment structure differs from target environments

### Why Common Directory Wins

| Factor | Common Directory | Module-Specific | Winner |
|--------|------------------|-----------------|--------|
| **Clarity** | ✅ High | ⚠️ Medium | Common |
| **Simplicity** | ✅ High | ⚠️ Medium | Common |
| **Version Control** | ✅ High | ❌ Low | Common |
| **Maintainability** | ✅ High | ⚠️ Medium | Common |
| **Scalability** | ✅ High | ⚠️ Medium | Common |
| **Extension-agnostic** | ✅ High | ❌ Low | Common |
| **Source/Target Mapping** | ⚠️ Medium | ✅ High | Module |

**Overall Winner**: **Common Directory** (6 wins vs. 1 win)

### Industry Alignment

The common directory approach aligns with industry best practices:

- **Kubernetes projects**: Common `manifests/` or `k8s/` directory
- **Ansible projects**: Common `group_vars/`, `host_vars/` directories
- **Terraform projects**: Common `terraform/` directory
- **Multi-application projects**: Centralized configuration

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

3. **Document deployment process**
   - Explain why files are in common directory
   - Show how deployment maps files from source to target locations
   - Explain source/target structure differences

4. **Use simple `.gitignore` patterns**
   - Ignore entire generated directory
   - Avoid per-file exclusions

5. **Add convenience tooling**
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

## Conclusion

The common directory approach (`vars/contexts/`) is the best choice for this project because:

1. ✅ **Multi-application project** benefits from consistency
2. ✅ **Complex deployment** already handles file mapping from source to target
3. ✅ **Clear separation** makes generated files obvious
4. ✅ **Simple version control** with one `.gitignore` pattern
5. ✅ **Scalable** structure for adding new contexts
6. ✅ **Extension-agnostic**: Variable-based configs without identifying extensions benefit from explicit segregation

The requirement for deployment tooling to map files from the source structure (`vars/contexts/`) to target locations is a necessary part of the deployment process, regardless of where files are generated. The common directory approach provides clarity and maintainability benefits that outweigh this mapping requirement.

