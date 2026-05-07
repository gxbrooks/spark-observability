# OTel dual-feed to Dynatrace

Dynatrace dual-feed is optional and additive.

- Existing exporters (`elasticsearch/*`, `otlp/tempo`) remain unchanged.
- Dynatrace exporter is enabled only when `DT_INGEST_TOKEN` is non-empty.
- Traces and metrics pipelines append `otlphttp/dynatrace`.

Endpoint:

- `{{ DT_API_URL }}/v2/otlp`

Auth header:

- `Authorization: Api-Token {{ DT_INGEST_TOKEN }}`
