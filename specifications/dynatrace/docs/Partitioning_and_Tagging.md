# Partitioning and tagging

This tenant is shared, so partitioning is done in-tenant.

## Partitioning primitives

- Host group: `spark-observability`
- Kubernetes cluster name: `spark-observability-k8s`
- Management zone: `Spark Observability`
- Auto tags:
  - `Project:spark-observability`
  - `Environment:lab`
  - `OwnedBy:gbrooks`

## Rule intent

- Management zone scopes entities to this project.
- Auto tags provide stable dimensions for dashboards, alerts, and API filters.
