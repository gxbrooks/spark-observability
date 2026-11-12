# Ansible-specific manual steps

For credential setup shared with Terraform (minting Dynatrace tokens), see
[`automation/docs/manual-steps.md`](../../docs/manual-steps.md). Everything below is specific to
Ansible's Service Graph Connector (SGC) automation — Terraform has no equivalent, since it
doesn't manage the ServiceNow-side SGC connector at all.

## Grant `connection_admin` (one-time)

`playbooks/servicenow/sgc/sources/dynatrace/deploy.yml` provisions the SGC credential itself (the
`api_key_credentials` table is writable by the automation user), but the **Hostname** lives on an
`http_connection` record gated by the `connection_admin` role. Grant it once — in **ServiceNow**,
not Dynatrace (`admin_brooks_lab` is a ServiceNow user):

1. **All → User Administration → Users**, open `admin_brooks_lab`.
2. **Roles** related list → **Edit** → add `connection_admin` → **Save**.
3. Re-run `playbooks/servicenow/sgc/sources/dynatrace/deploy.yml`; it sets the Hostname
   automatically.

After deploy, optionally run the Basic card's **Test Connection** task in Guided Setup (see
[`events/docs/deploy.md`](../playbooks/servicenow/sgc/sources/dynatrace/docs/deploy.md)'s Guided
Setup map) as a sanity check.

## Manual fallback — configure the connection via Guided Setup

Only needed when `DT_TOKEN_ADMIN_TOKEN` or the `connection_admin` role grant above is
unavailable. Use the **Basic** card (**Get Started**) in **Dynatrace Observability → Setup**. If
a form complains "…but Global is the current application", switch the application picker to the
connector app.

1. Generate the token in Dynatrace (**Access Tokens** →
   `https://<env-id>.live.dynatrace.com/ui/access-tokens` → **Generate new
   token**): name `dynatrace-servicenow-sgc-integration`, **Template: None**,
   scopes `entities.read`, `DataExport`, `ReadConfig` (see
   [`automation/docs/manual-steps.md`](../../docs/manual-steps.md)'s
   `dynatrace-servicenow-sgc-integration` section). Copy the `dt0c01.…` value immediately — it is
   shown only once.
2. **Configure Auth Token for Dynatrace** — in the pre-created *Dynatrace API Key* record,
   overwrite **API Key** with the literal text `api-token`, one space, then the token value (a
   bare token fails with 401 "invalid Api-Token", KB2288188). Leave **API Key
   Header**/**Prefix** empty and all other fields at their defaults; click **Update**.
3. **Configure HTTP Connection for Dynatrace** — **Hostname** = the classic environment URL
   `https://<env-id>.live.dynatrace.com` (no trailing `/api`; never a `*.apps.dynatrace.com`
   platform URL).
4. **Test Connection** — must report success.

For the remaining two Basic tasks (*Create Default Notification Payload Template*, *Upgrade
Source Native Keys*), see the Guided Setup map in
[`events/docs/deploy.md`](../playbooks/servicenow/sgc/sources/dynatrace/docs/deploy.md) — Mark as
Complete without running them.
