# Dynatrace observability module

This directory contains Dynatrace-specific assets for the platform split where
`elastic` and `dynatrace` are co-equal observability backends selected by the
`OBSERVABILITY_PLATFORM` / `observability_platform` flag in Ansible playbooks.

## Contents

- `docs/` architecture and operational guidance for Dynatrace.
- `dynakube/dynakube.yaml.j2` Dynatrace Operator CR (`cloudNativeFullStack`).
- `management-zone/` Settings 2.0 payload for partitioning.
- `automatic-tags/` Settings 2.0 payloads for partitioning tags (`spark-observability-tags.json.j2` renders three `builtin:tags.auto-tagging` objects).
- `otel-exporter/` snippet used for OTel dual-feed into Dynatrace.

## Partitioning model

The tenant is shared, so partitioning is done in-tenant:

- Host group: `spark-observability`
- Kubernetes cluster: `spark-observability-k8s`
- Management zone: `Spark Observability`
- Auto tags: `Project:spark-observability`, `Environment:lab`,
  `OwnedBy:gbrooks`

## Lifecycle

Playbooks live in `ansible/playbooks/observability/dynatrace/` and follow:
`install`, `deploy`, `start`, `stop`, `diagnose`, `test`, `uninstall`.

## Git as source of truth (idempotent Settings)

Management zones and automatic tags are defined under `management-zone/` and
`automatic-tags/` in this repo. `deploy.yml` (tag `partitioning`) **lists**
existing `builtin:management-zones` / `builtin:tags.auto-tagging` objects,
then **creates** (POST) or **updates** (PUT by `objectId`) so re-runs do not
duplicate settings. Changes belong in Git first, then apply via Ansible.

`DT_API_TOKEN` needs **settings.read** and **settings.write**.

## DynaKube / Kubernetes monitoring

`dynakube/dynakube.yaml.j2` sets Operator feature annotations for **automatic
Kubernetes API monitoring** and the **cluster display name** (must match
`DT_K8S_CLUSTER_NAME`). Without these, the UI can show **Monitoring not
available** for the cluster even when nodes report to Dynatrace.
