# Affected CIs in Change Window

Table API representation for `em_maintenance_rule`. Deploy loads
`em_maintenance_rule_affected_cis.json` and POSTs or PATCHes it. Another
tool or a manual client can apply the same document.

OOTB **CI in Change Window** marks only `change.cmdb_ci`. This rule covers
Affected CIs (`task_ci.ci_item`) for the same window:

- Change is **Scheduled** (−2) or **Implement** (−1). New is not enough.
- `approval=approved`, not on hold.
- Now is between planned `start_date` and `end_date`.
- Date comparisons use `javascript:gs.nowNoTZ()` so the Maintenance
  Calculator evaluates them at run time.

Keep `advanced` false. Advanced `findCisInMaint()` scripts are easy to drop
(wrong return type). A fallback script lives in `em_maint_affected_cis.js`
and is not part of deploy.

Apply with the Table API (create when the name does not exist):

```bash
curl -s -u "$SN_USER:$SN_PASSWORD" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -X POST "$SN_URL/api/now/table/em_maintenance_rule" \
  --data-binary @em_maintenance_rule_affected_cis.json
```
