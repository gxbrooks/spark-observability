# em-alert-enrich-sgo

Table API representation for `sys_script` (business rule metadata). The
script body is `em_alert_enrich_sgo.br.js`; deploy adds it as `script`.

## Why order 90

The rule must run before ServiceNow's own order-100 `em_alert` before-BRs
(Calculate correlation rule, TBAC Tag Normalization BR, Populate TBAC
Reasoning, Add message key if missing). Those evaluate the alert's fields as
they stand at that order, so the `metric_name` / `cmdb_ci` /
`sn-metric-class` backfill has to land first, or correlation and TBAC
clustering both evaluate stale (empty) data. The rule previously ran at 5000
(after those OOTB rules), which is why neither the L2I correlation rule nor
the metric_class TBAC ever correlated anything on the lab instance.
