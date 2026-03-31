# Global documentation (`docs/`)

This directory holds **repository-wide** documentation: concepts and runbooks that span **Ansible**, **Spark**, **observability**, **elastic-agent**, and **vars**.

**Module-specific** docs live next to their code:

| Area | Path |
|------|------|
| Observability (Prometheus, Tempo, stack architecture) | `observability/docs/` |
| Elasticsearch (indices, ILM, API client) | `observability/elasticsearch/docs/` |
| Grafana | `observability/grafana/docs/` |
| Elastic Agent | `elastic-agent/docs/` |
| Linux client bootstrap | `linux/docs/` |

## Entry points

| Document | Description |
|----------|-------------|
| [Lab_Topology_and_Resources.md](Lab_Topology_and_Resources.md) | **Lab1 / Lab2 / Lab3 roles, service placement, resource caps (target).** |
| [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) | Project summary, setup, Spark/Kubernetes playbooks. |
| [File_System_Architecture.md](File_System_Architecture.md) | DevOps vs Ops paths, NFS, Docker/K8s mounts. |
| [Application_Locations.md](Application_Locations.md) | Where tools and UIs live (URLs, venv, CLI). |

If a document applies to only one subsystem, prefer adding or linking from the **`*/docs/`** folder for that subsystem so global `docs/` stays navigable.
