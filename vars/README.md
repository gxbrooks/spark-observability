# Project variables (data plane)

This directory holds **spark-observability** variable definitions and generated
context files. The generator itself lives in the separate
**[context-variables](https://github.com/gxbrooks/context-variables)** package.

## Contents

| Path | Role |
|------|------|
| `variables.yaml` | Single source of truth for values and context tags |
| `contexts.yaml` | Output formats and filenames |
| `secrets.yaml` | Local secrets (gitignored) — see `secrets.example.yaml` |
| `secrets.example.yaml` | Template for `secrets.yaml` |
| `contexts/` | Generated outputs (gitignored) |

## Generate contexts

Install `context-variables` (apt/`dpkg` or `packaging/install.sh`), then:

```bash
generate-contexts --vars-dir "$(pwd)" -f
# or from repo root:
generate-contexts --vars-dir ./vars service-now -v

vars-grid --vars-dir ./vars --summary
```

Ansible playbooks call `generate-contexts` via
`ansible/playbooks/tasks/regenerate_contexts.yml`.

## Documentation

Operator and design docs: `context-variables` package
(`/opt/context-variables/docs/` or the GitHub repo), especially
`docs/usage.md` and `docs/Context_Variable_Best_Practice.md`.
