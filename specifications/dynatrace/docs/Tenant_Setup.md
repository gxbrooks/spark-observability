# Dynatrace tenant setup

Tenant: `https://pdt20158.apps.dynatrace.com`

## Required tokens

- `DT_TOKEN_ADMIN_TOKEN` (bootstrap, token lifecycle API)
- `DT_PAAS_TOKEN` (OneAgent installer download)
- `DT_OPERATOR_TOKEN` (Operator/Dynakube control-plane integration; for Kubernetes API monitoring Dynatrace documents **Read settings** / **Write settings** and related API access alongside standard ingest scopes—match the [Kubernetes monitoring prerequisites](https://docs.dynatrace.com/docs/ingest-from/setup-on-k8s/how-it-works/kubernetes-monitoring) for your tenant version)
- `DT_API_TOKEN` (Settings 2.0 for management zone and tags)
- `DT_INGEST_TOKEN` (OTLP ingest for OTel dual-feed)

## Where secrets are stored

Local-only in `vars/secrets.yaml` (gitignored), under the `dynatrace:` block
with uppercase variable names.
