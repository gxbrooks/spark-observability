# Dynatrace architecture (Phase 1)

## Scope

Phase 1 adds Dynatrace as an alternative observability backend while preserving
the current Elastic/Grafana path.

## Components

- OneAgent on `Lab1`, `Lab2`, `Lab3`.
- Dynatrace Operator on Kubernetes (`Lab3` control plane).
- Dynakube in `cloudNativeFullStack` mode for Kubernetes + workload visibility.
- Optional OTel Collector dual-feed to Dynatrace OTLP ingest.

## Placement

- Host-level OneAgent: all Lab hosts.
- Operator + Dynakube: Kubernetes cluster (`kubernetes_master` group).
- Existing Docker observability stack remains on `observability` (`Lab3`).

## Control flag

- `OBSERVABILITY_PLATFORM=elastic` (default): current behavior.
- `OBSERVABILITY_PLATFORM=dynatrace`: Dynatrace playbooks selected in umbrella
  lifecycle playbooks.
