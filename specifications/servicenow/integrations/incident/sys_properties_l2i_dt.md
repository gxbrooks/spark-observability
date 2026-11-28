# Spark L2I Dynatrace sys_properties

`sys_properties_l2i_dt.json.j2` uses the Terraform `templatefile()` subset.
Deploy supplies both values from secrets / context vars:

- `sn_l2i_dt_apps_url`: `DT_TENANT_URL` (or `dynatrace.DT_TENANT_URL`),
  trailing slash removed (`https://…apps.dynatrace.com`).
- `sn_l2i_dt_platform_token`: `dynatrace.DT_SERVICENOW_TOKEN` (class 3 in `vars/docs/secrets.md`),
  a Grail bearer with `storage:logs:read` and `storage:buckets:read`.
  The entry is marked `secret`, so its value is masked in deploy output.

Deploy skips a property whose value is empty and warns.
