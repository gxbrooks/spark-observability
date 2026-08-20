# OTel dual-feed to Dynatrace

Dynatrace dual-feed is optional and additive.

- Existing exporters (`elasticsearch/*`, `otlp/tempo`) remain unchanged.
- The `otlphttp/dynatrace` exporter **must** be nested under `exporters:` in
  `observability/otel-collector/otel-collector-config.yaml`. A top-level key of
  the same name makes the collector refuse to start
  (`'otelcol.configSettings' has invalid keys: otlphttp/dynatrace`).
- Dynatrace exporter is enabled only when `DT_INGEST_TOKEN` is non-empty.
- Traces and metrics pipelines append `otlphttp/dynatrace`.

Endpoint:

- `{{ DT_API_URL }}/v2/otlp`

Auth header:

- `Authorization: Api-Token {{ DT_INGEST_TOKEN }}`
