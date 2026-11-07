# Elasticsearch/Kibana Config File Naming Convention

**Scope:** every file under `specifications/elasticsearch/**` that
represents an Elasticsearch or Kibana object created by
`automation/ansible/scripts/elasticsearch/init-index.sh` (ILM policies,
index templates, ingest pipelines, transforms, Kibana data views, saved
searches, and dashboards).

## The rule

**The filename stem (everything before the type suffix) must exactly
match the live object's name or ID** — the same string used as the
`esapi`/`kapi` URL path segment (`PUT /_ilm/policy/<name>`, `PUT
/_index_template/<name>`, `PUT /_ingest/pipeline/<name>`, `PUT
/_transform/<name>`, `POST /api/saved_objects/search/<id>`) or, for data
views, the `data_view.id` field inside the file itself.

This is what lets tooling discover every object of a given type with a
single `fileset("**/*.<suffix>.json")` glob and apply it with the live
name read straight from the filename — no separate name-lookup table, and
no risk of a file's content silently diverging from the object it's
meant to represent.

## Type suffixes

All suffixes are dot-separated (`<name>.<type>.json`) — no exceptions:

| Suffix | Elasticsearch/Kibana object |
|---|---|
| `.ilm.json` | ILM policy (`PUT /_ilm/policy/<name>`) |
| `.template.json` | Index template (`PUT /_index_template/<name>`) |
| `.pipeline.json` | Ingest pipeline (`PUT /_ingest/pipeline/<name>`) |
| `.transform.json` | Transform (`PUT /_transform/<name>`) |
| `.dataview.json` | Kibana data view (`POST /api/data_views/data_view`; id comes from the file's own `data_view.id`) |
| `.search.json` | Kibana saved search (`POST /api/saved_objects/search/<id>`) |
| `.dashboard.json` | Kibana dashboard (no live automation creates these today — manually built in Kibana, exported here for version control/backup) |

A file's stem may itself contain hyphens or underscores (live ES/Kibana
names sometimes do, e.g. `logs-spark_gc-default`) — only the type suffix
is reserved.

## Verifying a file follows the rule

Grep `init-index.sh` for the file's path and check the name in the
preceding `esapi`/`kapi` URL against the filename stem:

```bash
grep -B1 "<category>/<file>" automation/ansible/scripts/elasticsearch/init-index.sh
```

For `.dataview.json` files, check `data_view.id` in the file itself
instead — it's self-declared, not chosen by the caller.

## Exceptions

- **`*.index.json`, `*.watcher.json`, `README.md`** and other files that
  aren't one of the seven types above are out of scope for this
  convention (they don't have a corresponding fileset-driven discovery
  need).
- **`batch-metrics/`** is deprecated (see
  `batch-metrics/README.md`) and not initialized by
  `init-index.sh`'s main run. Its files are exempt — don't rename them
  as part of maintaining this convention.
- **`.dashboard.json`** has no live naming authority to match against
  (nothing currently creates dashboards programmatically), so the
  filename stem simply *becomes* the object's designated ID whenever
  dashboards are brought under automated management.

## History

This convention was formalized after an audit found the filename stem
and the live object name had drifted apart in roughly 30 files (e.g.
`gpu-metrics.template.json` was actually the `metrics-gpu-default`
template; `spark-gc-ingest-pipeline.json` was actually the
`logs-spark_gc-default` pipeline). All existing files were renamed to
restore the 1:1 correspondence — see `tmp/terraform_ansible_learnings.md`
for the full rename log.
