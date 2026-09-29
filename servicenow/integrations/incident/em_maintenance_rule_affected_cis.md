# Affected CIs in Change Window

Table API representation for `em_maintenance_rule`. Deploy loads
`em_maintenance_rule_affected_cis.json` and POSTs or PATCHes it. Another
tool or a manual client can apply the same document.

## Why this rule exists

OOTB **CI in Change Window** (`SNC.ImpactManager.getCisInActiveChangeWindow()`)
marks only `change.cmdb_ci`. Affected CIs live on `task_ci` and are a known
product gap; industry practice is a second non-advanced maintenance rule on
`task_ci` / `ci_item` (ServiceNow Community / partner pattern).

## Semantics (aligned with OOTB primary-CI behavior)

This extension mirrors what OOTB does for `change.cmdb_ci` on this instance
(verified against `em_impact_maint_ci`), plus the Event Management planned-**or**-
actual time gate:

1. State is **Scheduled** (`-2`) or **Implement** (`-1`). **New (`-5`) does not
   qualify** — OOTB does not mark the primary CI while the change is still New.
2. `approval=approved`, and the change is **not** on hold.
3. Current time is inside the **planned** start/end window **or** the **actual**
   start/end window (`work_start` / `work_end`). While Implement has set
   `work_start` and `work_end` is still empty, the actual window is open-ended.
4. The CI to mark is each `task_ci.ci_item` (not `change.cmdb_ci`).

Date comparisons in the deployed filter use `javascript:gs.nowNoTZ()` so the
Maintenance Calculator evaluates them at run time.

Keep `advanced` false. Advanced `findCisInMaint()` scripts are easy to drop
(wrong return type). A fallback script lives in `em_maint_affected_cis.js`
and is not part of deploy. If used, it must `return JSON.stringify(cis)`.

Apply with the Table API (create when the name does not exist):

```bash
curl -s -u "$SN_USER:$SN_PASSWORD" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -X POST "$SN_URL/api/now/table/em_maintenance_rule" \
  --data-binary @em_maintenance_rule_affected_cis.json
```
