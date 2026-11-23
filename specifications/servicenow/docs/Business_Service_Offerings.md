# Business Service Offerings — CSDM schema addition

## Why

ServiceNow's own CSDM documentation and community guidance confirm the
structure requested for Business Service Offerings (BSO):

- The BSO's **native `parent` field** references the owning Business/Technical
  Service — this *is* the out-of-box "parent" relationship
  (see [Relationships between CSDM objects](https://www.servicenow.com/docs/r/UUPLjuAXTo4SlQO8Ml6ZjQ/7YUcVy3vgl35fsGte05JzA):
  "the parent for service offering (SO3) is business service (BS1)"). **Confirmed
  live on `optimizincdemo1` (2026-11-18):** the actual BSO table on this
  instance is **`service_offering`** (label "Offering", extends
  `cmdb_ci_service`), not `cmdb_service_offering` as generic ServiceNow
  community docs assume — verified via `sys_db_object` (`labelLIKEOffering`).
  Verify the table name per instance before relying on the literal string.
- The link from an **Application Service / Service Instance to a
  Service Offering is a CI relationship (`cmdb_rel_ci`), not a containment/
  parent field** — see
  [Application services](https://www.servicenow.com/docs/r/GCPjp~ldPTNRN99oH1DYFg/HrURtlAgKmcGGo0~VtjVFg):
  "CSDM lets you add relationships between application services and
  Business Application, Technical Service Offerings, or Business Service
  Offerings."

So the correct shape is:

```
Business Application
  └─ Contains::Contained by ─ Business Service
                                  ├─ parent ─ Business Service Offering
                                  └─ Contains::Contained by ─ Service Instance ── (rel) ── Business Service Offering
```

The Business Service and the Business Service Offering are **not** peers —
the BSO's `parent` field is the BS. The Business Service keeps its existing
`Contains::Contained by` edge to the Service Instance (unchanged, normative
CSDM hierarchy); the Service Instance gets an **additional** CI relationship
to the BSO so that alert-rule CI → Service Instance → (first) BSO/BS
resolution works in one hop from the Service Instance.

**Flag for review:** multiple ServiceNow community threads report that
having a `cmdb_ci_service_calculated` (Dynatrace SGC-discovered) service
*and* a separate tag-based (`cmdb_ci_service_by_tags`) service for the same
underlying workload, bridged only by a shared tag, is not an officially
supported hybrid pattern —
see ["Switch from Calculated Application Service Map to Tag-Based Application Service Map?"](https://www.servicenow.com/community/itom-forum/switch-from-calculated-application-service-map-to-tag-based/m-p/2857446)
and ["How to convert a Calculated application service into a tag based application service?"](https://www.servicenow.com/community/common-service-data-model-forum/how-to-convert-a-quot-calculated-application-service-quot-in-to/m-p/3481467).
This repo's own design rule in `Log_to_Incident.adoc` ("No CMDB relationship
between service instances and workloads") says the tag-based service
instance should only ever gain flat `svc_ci_assoc` membership to workload
CIs — not to another service. The bridge pattern described by the author
(manually creating a service instance, then tagging the Dynatrace-created
calculated service so it gets swept into the same tag-based membership) is
most likely how the Calculated Application Service ended up appearing as a
second "level" under the Tag-Based Application Service in the brooks-lab
instance. Revisit whether the Dynatrace SGC-discovered calculated service
should carry the `servicenow.com/service-instance` tag at all, independent
of the BSO fix below.

## New YAML fields

### `business_service_offerings` (new top-level list)

Same shape as `business_services`, plus `parent_business_service` (required):

```yaml
business_service_offerings:
  - name: Apache Spark - Production
    identifier: apache-spark-production
    short_description: Production offering of Apache Spark service instances
    operational_status: "1"
    parent_business_service: Apache Spark
    owned_by: gbrooks
    business_criticality: "4 - not critical"
```

Naming convention: `<Business Service name> - <environment>` (for example
`- Production`, `- Test`). `identifier` is the slugged form.

### `service_instances[].service_offering` (new optional field)

```yaml
service_instances:
  - name: Spark History Server
    parent_business_service: Apache Spark
    service_offering: Apache Spark - Production
    ...
```

`parent_business_service` is unchanged (BA/BS/SI `Contains::Contained by`
hierarchy). `service_offering` is additive: it names a
`business_service_offerings[].name` in the same spec (or a cross-file
reference, same resolution rules as `depends_on`) that the deploy processor
must link via a **CI relationship**, not a parent/containment edge.

## What the deploy processor (`sn-sync-inject`) does

Implemented in the sibling **`sn-sync`** repository
(`src/sn_sync/injector.py`, `config.py`, `loaders.py`, `validators.py`; see
that repo's `docs/CSDM_Specifications.md` Statements 2.1.1, 2.3a, 3.1.1–3.1.3a,
3.2.5–3.2.6 for the normative spec). Confirmed against the live
`optimizincdemo1` instance on 2026-11-18:

1. For each `business_service_offerings[]` entry, `_upsert_bso()` creates/updates
   a **`service_offering`** record (`class_name="service_offering"`) with `name`,
   `short_description`, `operational_status`, `business_criticality`, `owned_by`,
   and **`parent` = the resolved sys_id of `parent_business_service`** (lookup
   by name in `cmdb_ci_service`, same resolution helper already used for
   `parent_business_application` / `parent_business_service`).
2. For each `service_instances[]` entry with `service_offering` set, the
   service instance is queued (`offering_queue`) during `_upsert_as()` and
   linked by `link_offerings()` once the named BSO is known: it creates a
   `cmdb_rel_ci` row with **parent = BSO, child = Service Instance**, type
   **`Depends on::Used by`**. This instance's `cmdb_rel_type` table has no
   dedicated "Offering" relationship type (52 types enumerated live) — `Depends
   on::Used by` is the already-conventional type for this kind of edge
   (same type used for `depends_on`), so `resolve_rel_type()` looks it up by
   name rather than hardcoding a sys_id.
3. This link is deferred/idempotent like the rest of the deploy registry —
   a `service_offering` referencing a BSO not yet created in the run is a
   **deferred dependency** (same handling as `depends_on`), reported via
   `InjectReport.deferred_offerings` and retried on a later pass, mirroring
   `link_depends_on()`.

Unit-tested in `sn-sync/tests/test_injector_bso.py` (BSO `parent` field +
Service Instance → BSO relationship creation).

## Status

- [x] `specifications/servicenow/regions/brooks-lab/spark.csdm.yaml` updated
      with `business_service_offerings: [Apache Spark - Production]` and
      `service_offering` on all four Spark service instances.
- [x] `sn-sync-inject` code change — implemented in `sn-sync/src/sn_sync/`
      (`injector.py`, `config.py`, `loaders.py`, `validators.py`) and
      unit-tested.
- [x] Live relationships on `optimizincdemo1` checked: the Service Instance
      ↔ BSO `Depends on::Used by` relationships were **already correct** for
      all four Spark service instance/BSO pairs — no relationship-creation
      fix was needed there.
- [x] Live BS → BSO bug found and fixed: all four pre-existing BSO records
      (created earlier by a different user) had their `parent` field
      pointing at a stray, fully orphaned duplicate Business Service named
      **"Data Analytics | Spark"** instead of the CSDM-managed **"Apache
      Spark"** BS — this, not a schema/relationship-type problem, was the
      actual cause of the BS/BSO "peer instead of parent" symptom in the
      Service Portal map. Fixed by patching `parent` on all four BSO
      records to the correct BS `sys_id`.
- [ ] **Open question:** the "Data Analytics | Spark" Business Service CI
      (sys_id `c5a0250193641b9086b0f2f85d03d6ec`) is now fully disconnected
      (no relationships at all) after the fix above. Decide whether to
      retire/rename/delete it — not done yet, pending explicit confirmation.
- [ ] The other three region specs (`observability-platform.csdm.yaml`,
      `elastic-agent.csdm.yaml`, `dynatrace-monitoring.csdm.yaml`) were left
      as-is — apply the same `business_service_offerings` pattern there if
      wanted; not requested as part of this change.
- [ ] The separate "two levels of service instance" question (Tag-Based vs.
      Calculated Application Service, see "Flag for review" above) is
      unresolved and out of scope for this change.
