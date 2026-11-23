# Technical Management Services — CSDM schema addition

## Why

Everything this repo's CSDM specs modeled before this change (`business_applications` →
`business_services` → `business_service_offerings` → `service_instances`) is
the **business-facing** half of CSDM: application stacks the business uses
(Apache Spark, Dynatrace Monitoring, the observability platform).

A **Technical Management Service (TMS)** and its **Technical Management
Service Offering (TMO)** are the matching **infrastructure-facing** half:
a technical capability that IT operations manages directly, rather than
something the business uses as an application.

This request: model **"Linux Servers"** as a TMS, with a **"Linux Servers -
Production"** TMO, whose members come from a **Dynamic CI Group** of
Lab1, Lab2, and Lab3 rather than hand-picked relationships. Adding a
Lab4 later then means changing the group's query, not editing the TMS/TMO
spec.

## Confirmed live on `optimizincdemo1` (2026-11-22)

The draft of this doc could not reach the instance (it was written from a
sandbox with no route to it). The questions it left open were answered by
read-only Table API queries from Lab3 against `sys_db_object`,
`sys_dictionary`, `sys_choice`, `cmdb_rel_type_suggest`, `sys_script` (business
rules), and `sysauto_script` (scheduled jobs). As with BSO, the generic names
were wrong:

| Concept | Generic / assumed | Real on this instance |
| --- | --- | --- |
| TMS table | "Technical Service", or a classification on `cmdb_ci_service` | **`cmdb_ci_service_technical`**, label **"Technology Management Service"**, extends `cmdb_ci_service`. **Plus** `service_classification` = `Technical Service` (choice *value*; its *label* is "Technology Management Service"). No table is labelled "Technical Service" at all. |
| TMO table | its own table | **`service_offering`**, the same table as BSO. Told apart only by `service_classification` = `Technical Service`. |
| TMS → TMO link | ? | TMO's **native `parent` field**, same as BS → BSO. |
| Dynamic CI Group table | `cmdb_ci_group` | **`cmdb_ci_query_based_service`**, label **"Dynamic CI Group"**, extends `cmdb_ci_service_auto`. `cmdb_ci_group` exists but is a plain "Group" CI with no query behaviour. |
| DCG membership | encoded query, or a rule-based related list? | **Either.** The DCG has its own `table` (CI class) + `filter` (encoded query) fields, **and** a `cmdb_group` reference to a CMDB Group (whose members come from `cmdb_group_contains_encoded_query` / `_ci` / `_qb_query`). Both feed `SNC.QueryBasedServiceManager.updateSvcAssoc()`, which writes members to **`svc_ci_assoc`**. That runs on insert/update (business rule "Query Based Service Filter Updated") and every 10 minutes (scheduled job "Update Query Based Services"). |
| DCG → TMO link | parent field, or `cmdb_rel_ci`? | **`cmdb_rel_ci`, `Contains::Contained by`, parent = TMO, child = DCG.** The DCG has no field pointing at an offering. `cmdb_rel_type_suggest` lists exactly this pairing (`service_offering` → `cmdb_ci_query_based_service`, Contains, offering is parent). |
| Lab server CI names | `Lab1`, `Lab2`, `Lab3` | **`lab1`, `lab2`, `lab3`** (`cmdb_ci_linux_server`, location `brooks-lab`); the FQDNs are `Lab1.lan` / `Lab2.lan` / `Lab3.lan`. |

Also confirmed: no TMS, TMO, or Dynamic CI Group existed on the instance
beforehand (so there was no existing layout to follow), and nothing in
`cmdb_ci` was named like "Linux Server" (so no name collisions).

The resulting shape:

```
Technical Management Service "Linux Servers"              (cmdb_ci_service_technical)
  └─ parent field ─ TMO "Linux Servers - Production"      (service_offering, service_classification=Technical Service)
                      └─ Contains::Contained by ─ DCG "Linux Servers (brooks-lab)"  (cmdb_ci_query_based_service)
                                                    └─ svc_ci_assoc ─ lab1, lab2, lab3
```

**Design choice — `table` + `filter`, not a CMDB Group:** the deploy
processor writes membership on the DCG record itself. That is one record,
upserted by name and diffable field by field. A CMDB Group would add two
more records (`cmdb_group` and `cmdb_group_contains_encoded_query`, the
second with no natural key). It would also hit the "Check CMDB group
uniqueness" business rule, which allows only one DCG per CMDB group: one
more way to collide with someone else's work on a shared instance. See
`CSDM_Specifications.md` Commentary for the same reasoning.

## New YAML fields

### `technical_management_services` (new top-level list)

Same shape as `business_services`, but with **no** parent: a TMS is
top-level, not under a Business Application. The validator rejects
`parent_business_application` / `parent_business_service`.

```yaml
technical_management_services:
  - name: Linux Servers
    identifier: linux-servers
    short_description: Linux server infrastructure in the brooks-lab environment
    operational_status: "1"
    owned_by: gbrooks
    business_criticality: "4 - not critical"
```

### `technical_management_service_offerings` (new top-level list)

Same shape as `business_service_offerings`, with
`parent_technical_management_service` in place of `parent_business_service`.
Names must not match any BSO name (they share the `service_offering` table).

```yaml
technical_management_service_offerings:
  - name: Linux Servers - Production
    identifier: linux-servers-production
    short_description: Production offering of Linux server infrastructure
    operational_status: "1"
    parent_technical_management_service: Linux Servers
    owned_by: gbrooks
    business_criticality: "4 - not critical"
```

### `dynamic_ci_groups` (new top-level list)

```yaml
dynamic_ci_groups:
  - name: Linux Servers (brooks-lab)
    identifier: linux-servers-brooks-lab
    short_description: Lab1-Lab3 Linux server CIs, populated by query rather than hand-picked membership
    operational_status: "1"
    owned_by: gbrooks
    table: cmdb_ci_linux_server          # -> DCG.table
    condition: nameINlab1,lab2,lab3      # -> DCG.filter (encoded query)
    service_offering: Linux Servers - Production   # -> Contains::Contained by, TMO -> DCG
```

Compared with the draft: `offered_by` was renamed `service_offering` to
match `service_instances[].service_offering`. It still names an
offering, but here it becomes a `Contains` edge, not `Depends on`. The
condition was changed from `nameINLab1,Lab2,Lab3` to the real lowercase CI
names. `owned_by` and `operational_status` were added (required);
`business_criticality` is optional on a DCG.

## What the deploy processor (`sn-sync-inject`) does

Implemented in the sibling **`sn-sync`** repository (`src/sn_sync/config.py`,
`loaders.py`, `validators.py`, `injector.py`, `diff.py`, `delete.py`; normative
Statements 2.3b–2.3d, 3.1.1a, 3.1.2a, 3.2.7–3.2.9, 3.4.6–3.4.9 in that repo's
`docs/CSDM_Specifications.md`):

1. `_upsert_tms()` creates/updates a `cmdb_ci_service_technical` record with
   `service_classification=Technical Service` and stores its `sys_id` in
   `registry["technical_management_services"]`.
2. `_upsert_tmo()` resolves `parent_technical_management_service`, first from
   the registry and otherwise by a live lookup in `cmdb_ci_service_technical`. It
   then creates/updates a `service_offering` record with
   `service_classification=Technical Service` and **`parent` = TMS sys_id**. If
   the parent is missing, it fails with an error, same as BSO.
3. `_upsert_dcg()` resolves `service_offering` against the TMO registry, or
   live in `service_offering` filtered to `service_classification=Technical
   Service` so it can never pick up a same-named BSO. It then
   creates/updates a `cmdb_ci_query_based_service` record with `table` and
   `filter`, and ensures a `Contains::Contained by` `cmdb_rel_ci` row with parent=TMO,
   child=DCG. It never writes `svc_ci_assoc`; ServiceNow fills that in.
4. Order within a file: BA → BS → BSO → **TMS → TMO → DCG** → service
   instances. Delete runs in reverse (DCG → TMO → TMS).
5. `sn-sync-diff` reports all three kinds (TMO's `parent` and
   `service_classification` included), the TMO → DCG edge, and the DCG's
   `svc_ci_assoc` member count.

Unit-tested in `sn-sync/tests/test_injector_tms.py` (16 tests: the
TMS/TMO/DCG chain and request bodies, insert order, missing parents,
classification-filtered TMO lookup, and the validation rules). The full
suite passes: 38 tests.

## Applied to `optimizincdemo1` (2026-11-22)

`sn-sync-validate` returned OK. `sn-sync-diff` before inject showed all three
objects and the TMO → DCG edge as `missing`, with nothing else touched. Then
`sn-sync-inject --specs .../linux-servers.csdm.yaml` (this file only, not
the whole region) created:

| Object | Class | sys_id |
| --- | --- | --- |
| TMS `Linux Servers` | `cmdb_ci_service_technical` | `328a2f1893709f1086b0f2f85d03d6fe` |
| TMO `Linux Servers - Production` (parent → Linux Servers) | `service_offering` | `fa8a6f1893709f1086b0f2f85d03d648` |
| DCG `Linux Servers (brooks-lab)` | `cmdb_ci_query_based_service` | `7e8a6f1893709f1086b0f2f85d03d654` |
| `Contains::Contained by` TMO → DCG | `cmdb_rel_ci` | `978a6f1893709f1086b0f2f85d03d6be` |

Checked by reading the tables directly (not through sn-sync):
`svc_ci_assoc` for the DCG held exactly **lab1, lab2, lab3**
straight after insert. ServiceNow also set the DCG's own `service_classification` to
`Technical Service` on its own. A second inject was idempotent (records updated
in place, edge reported `exists`, no duplicates). `sn-sync-diff` afterwards:
**IN SYNC**.

## Status

- [x] Live verification of real table/field names (above).
- [x] Field shapes finalized; `regions/brooks-lab/linux-servers.csdm.yaml` updated.
- [x] Injector, loader, validators, diff, and delete support in `sn-sync`, plus unit tests.
- [x] Statements folded into `sn-sync/docs/CSDM_Specifications.md`.
- [x] `linux-servers.csdm.yaml` registered in `region.yaml`'s `csdm_specs`.
- [x] Applied to `optimizincdemo1` and verified.
- [ ] `sn-sync/docs/CSDM_Specifications.html` / `.pdf` are rendered copies
      and were **not** regenerated.
- [ ] Not done here: whether `Linux Servers` should also take
      `service_instances` / application-service relationships (for example
      Spark service instances `Depends on` the TMO). Not requested.
