# brooks-lab on two ServiceNow instances (Demo1 + Demo3) — plan

Living doc. Started 2026-11-23.

## Goal

The brooks-lab environment feeds **optimizincdemo1** and **optimizincdemo3** at the
same time:

- one MID Server per instance on Lab3, both running concurrently;
- Discovery, CSDM, SGC, and incident playbooks can target either instance;
- Dynatrace sends problems (ServiceNow events) to **both** instances.

Demo3 starts on the legacy **SGC for Dynatrace** (`sn_dynatrace_integ`, the connector
Demo1 runs). It moves to **SGC for Dynatrace SaaS** once ServiceNow fixes Demo3's
install/uninstall problem.

## Design

### Instance registry (single source of truth)

`vars/variables.yaml` gains `SN_INSTANCES` (service-now context), a list of entries
keyed by `id`, plus `SN_DEFAULT_TARGET: demo3`. It is a list rather than a map
because the context generator writes nested maps at column 0, which breaks them. Each entry holds the per-instance
non-secret values that are scalars today:

| Field | demo1 | demo3 |
| --- | --- | --- |
| `url` | `https://optimizincdemo1.service-now.com` | `https://optimizincdemo3.service-now.com` |
| `short_name` | `optimizincdemo1` | `optimizincdemo3` |
| `secrets_suffix` | `""` | `_DEMO3` |
| `mid_server_name` | `mid-brooks-lab3` (unchanged, live) | `mid-brooks-lab3-demo3` |
| `mid_service_name` | `mid_brooks_lab3` (unchanged, live) | `mid_brooks_lab3_demo3` |
| `mid_agent_dir` | `/opt/servicenow/mid/agent` (unchanged, live) | `/opt/servicenow/mid-demo3/agent` |
| `mid_installer_deb_url` | current Zurich build | Australia patch5b build |
| `dt_legacy_connector_sys_id` | `712a39811…` | `""` (Demo3 uses SGC) |
| `dt_problem_notification_name` | `ServiceNow brooks-lab - Spark Observability` (unchanged) | `ServiceNow brooks-lab (demo3) - Spark Observability` |
| `dt_sgc_api_token_name` | `dynatrace-servicenow-sgc-integration` (unchanged, live) | `dynatrace-servicenow-sgc-integration-demo3` |
| `incident_deploy_enabled` | `true` | `false` (held: shared Event Management) |

Playbooks select an instance with **`-e target=demo1|demo3|all`**. The default is
`SN_DEFAULT_TARGET` = `demo3` (changed 2026-11-23; the selector was
`-e SN_INSTANCE=<id>` with default `demo1` before that).

- Every ServiceNow playbook first imports `playbooks/servicenow/common/target.yml`.
  That play validates `target`.
- For `all`, the outermost ServiceNow playbook re-runs itself once per remaining
  instance as a child `ansible-playbook -e target=<id>`. It gets the same inventory,
  `-e` values, tags, `--limit`, verbosity and check/diff. The flags are read through
  `lookup_plugins/sn_cli_args.py`, and child logs go to `automation/ansible/tmp/`.
- The parent then continues against the first entry (demo1). Fan-out is once per run,
  so aggregators and the whole-lab playbooks re-run only the ServiceNow playbook.
- A failed child stops the run.
- Deploy facts are per instance for every instance:
  `vars/contexts/servicenow_*_deploy_<id>.json`. Demo1's files were renamed to `_demo1`.
- `incident/deploy.yml` skips instances with `incident_deploy_enabled: false`.

Every `servicenow/*/common/vars.yml` derives `sn_url`, `sn_user`, `sn_password`,
`sn_mid_*`, and so on from the selected entry. Secrets come from `servicenow.<KEY><suffix>`
(`SN_USER_DEMO3`, `SN_DT_WEBHOOK_USER_DEMO3`, …).

`SN_URL` stays as Demo1's URL for the non-Ansible readers (`servicenow/comparator`,
`create-sn-change-window.py`, the generated shell contexts). Those readers still act
only on Demo1. In particular, `create-sn-change-window.py` opens Spark change windows
on Demo1 only.

### Second MID Server on Lab3

The vendor `.deb` is one `agent` package that unpacks to `/opt/servicenow/mid/agent`,
so a second package install is impossible. For any instance whose `mid_agent_dir` is
not the package path, `install_mid_server.yml` will:

1. `dpkg-deb -x` that instance's installer `.deb` into a staging dir and copy
   `opt/servicenow/mid/agent` to `mid_agent_dir`, owned by `servicenow-mid`;
2. run `installer.sh -silent` there with that instance's URL, MID user, `-MID_NAME`, and
   `-APP_NAME` (the systemd unit name);
3. write a **per-service** sudoers file. Today it is one fixed file,
   `/etc/sudoers.d/servicenow-mid`, which a second install would overwrite, breaking
   Demo1's MID auto-upgrade.

Two existing bugs get fixed along the way:
- the agent path is found by `find /opt/servicenow -name agent | first`, which is
  ambiguous once two agents exist; it becomes explicit per instance;
- `diagnose.yml` checks the nonexistent `/opt/servicenow/mid-brooks-lab3`.

Capacity: Lab3 has ~34 GiB available and 246 GB disk free. A second MID JVM uses
`-Xmx1024m`, which fits.

### Dynatrace → both instances

`events/deploy.yml` upserts one problem notification by display name. Run it once per
instance (`-e target=all`, or `demo1` and `demo3` separately). Each run produces a separate notification
with that instance's name, URL, and webhook auth. Both use the same brooks-lab alerting
profile, so the same problems go to both instances.

Not touched: `ServiceNow Demo 1 - Optimiz` and the pre-existing
`ServiceNow optimiz demo3` notification. The second one is someone else's, and the
new brooks-lab Demo3 notification is a separate object.

Webhook auth secrets get per-instance keys (`SN_DT_WEBHOOK_USER_DEMO3`, …).

### SGC for Dynatrace on Demo3

`sgc/install.yml` → `sgc/deploy.yml` → `sgc/sources/dynatrace/deploy.yml` with
`-e target=demo3` (now the default). The SGC connection mints its own Dynatrace token per instance.
Moving to "SGC for Dynatrace SaaS" later only changes the SGC install/source step.
The instance registry and the MID/notification split stay as they are.

## Steps

| # | Step | Needs | Status |
| - | ---- | ----- | ------ |
| 1 | Instance registry + selector in all six `servicenow/*/common/vars.yml` (now `-e target=demo1\|demo3\|all`, default demo3) | repo only | **done** |
| 2 | Per-instance secrets keys, incl. webhook auth (`SN_DT_WEBHOOK_*_DEMO3`) | repo only | **done** |
| 3 | Multi-MID `install_mid_server.yml`, per-service sudoers, explicit agent path, diagnose fix | repo only | **done** (not yet run for Demo3) |
| 4 | Per-instance Dynatrace notification name and SGC token name; legacy-path guard; docs | repo only | **done** |
| 5 | Regression on Demo1: `discovery/diagnose.yml` and `events/diagnose.yml` | Demo1 (read-only) | **done**, both pass with 0 changes |
| 6 | Demo3 credential check (read-only) | working Demo3 admin password | **done**: login OK, `admin` granted 2026-11-23 |
| 7 | Demo3: create `mid_brooks_lab` (mid_server role) | step 6 | **done**: Machine identity, web-service only, `mid_server` only; login verified |
| 8 | Demo3 build → `mid_installer_deb_url` | step 6 | **done**: Australia patch5b (`glide.war`); URL returns 200 |
| 9 | Install Demo3 MID on Lab3, validate Up | steps 7–8 | **done**: `mid-brooks-lab3-demo3` Up, validated; both units active |
| 10 | Demo3 Discovery deploy (brooks-lab location, schedule) | step 9 | **done**: location and schedule already existed; MID validated; first `discover.yml` run not yet done |
| 11 | Demo3 SGC for Dynatrace (legacy) install + source deploy | step 6 | **done** 2026-11-23: already installed (v1.13.1); Gary approved taking over Demo3's SGC config; source deploy applied |
| 12 | Dynatrace notification → Demo3; end-to-end problem test on both | step 11 | **done**: same problems processed on both instances |
| 13 | CSDM / incident playbooks on Demo3 | step 11 | **partial** 2026-11-23: service-mapping and CSDM deployed (43 objects); incident deploy held (`incident_deploy_enabled: false`) |
| 14 | `target` flag (`demo1`/`demo3`/`all`, default `demo3`) on every ServiceNow playbook | repo only | **done** 2026-11-23: tested invalid / default / demo1 / all, plus `servicenow/diagnose.yml -e target=all` |

### Demo3 commands (run from `automation/ansible/`; `demo3` is the default target)

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/diagnose.yml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/install.yml --tags mid_server
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/deploy.yml
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/install.yml
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/deploy.yml
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/deploy.yml
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/deploy.yml
```

## Findings (2026-11-23)

- **Demo3 login:** the first stored `SN_PASSWORD_DEMO3` was a ServiceNow password
  hash and returned 401. After Gary reset the password, the login works (200) and the
  account is active.
- **Demo3 roles:** `admin_brooks_lab` has 160 active roles, but **not** `admin`,
  `user_admin`, `security_admin`, `sn_appclient.store_admin`, or `evt_mgmt_admin`.
  It does have `discovery_admin`, `cmdb_inst_admin`, `itil`, `evt_mgmt_integration`,
  `sn_appclient.app_client_user`, `rest_service`, and `mid_server`. Consequences:
  - reading `sys_scope` returns 403 and `sys_store_app` fails API ACL, so the playbooks
    cannot see which Dynatrace apps are installed, and an App Manager install will not
    be allowed;
  - the account cannot create the `mid_brooks_lab` user;
  - `glide.buildtag` is not readable, so the MID .deb URL cannot be derived.
  Per the run rules, I stopped here and made no Demo3 writes.
- **Dynatrace tenant, problem notifications:**

  | Name | State | Target |
  | ---- | ----- | ------ |
  | `ServiceNow Demo 1 - Optimiz` | enabled | Demo1 legacy connector `712a3981…` (not ours) |
  | `ServiceNow brooks-lab - Spark Observability` | enabled | Demo1 `source=SGO-Dynatrace` (ours) |
  | `Legacy Demo 3` | enabled | Demo3 legacy connector `4d2f61174728db503a869b83616d4386`, `Otel Demo` profile, no auth header (not ours) |
  | `ServiceNow optimiz demo3` | **disabled** | an httpdump.app URL, not Demo3 (not ours) |

  So Demo3 already accepts Dynatrace events through a legacy EM push connector.
  That connector could serve as a stop-gap target for brooks-lab problems before SGC
  is on Demo3. It belongs to someone else, though, so that is Gary's call.
- **Shared Dynatrace SGC token name (fixed).** Both instances would have minted
  `dynatrace-servicenow-sgc-integration`. Demo3 would then have skipped minting
  because the token "exists", and a rotation on one would have deleted the other's.
  Non-default instances now use `…-<id>`.
- **Demo3 apps:** `sn_dynatrace_integ` (legacy SGC) **v1.13.1 is already installed and
  active**; `sn_dynatrace_saas` v1.2.0 is installed but **inactive**. `sgc/install.yml`
  therefore installed nothing (0 changes); it re-requested activation of two plugins
  (HTTP 200, no-op if already active). The repo pin is v1.15.0, so expect drift warnings.
- **Demo3 build:** Australia patch5b. Demo1 is on Zurich, so each MID has its own installer.
- **Demo3's legacy SGC is someone else's configuration.** `sources/dynatrace/deploy.yml`
  and `events/deploy.yml` write instance-wide objects, and on Demo3 those already exist:
  | Object | Current state on Demo3 | What our deploy would do |
  | --- | --- | --- |
  | `sn_dynatrace_integ_connections` (only row, alias `Dynatrace_Connection`) | created by `admin` 2022, status Pending | set management zone to the Spark MZ |
  | `http_connection` "Dynatrace Connection" | host `mjm80413.live.dynatrace.com` (not brooks-lab's tenant) | repoint to `pdt20158` |
  | `api_key_credentials` "Dynatrace API Key" | `admin`, 2024-09-26 | overwrite with a brooks-lab token |
  | `sn_dynatrace_integ.management_zone_*` properties | empty (= all zones) | set to the Spark MZ |
  | Scheduled import "SGO-Dynatrace Hosts" | **deactivated by ksanders 2026-11-20** | reactivate |
  | `sn_dynatrace_integ.events_for_unmatched_ci.enabled` | (instance-wide) | set to true |
  Other people configured the Dynatrace SaaS connector on Demo3 three days ago (ksanders,
  oawwad), so I did not run either deploy. This needs Gary's decision.
- **Deploy-facts files are now per instance (fixed).** `discovery/deploy.yml` wrote
  Demo3's sys_ids into the then-shared `vars/contexts/servicenow_discovery_deploy.json` (now one `_<id>` file per instance).
  Non-default instances now write `…_deploy_<id>.json` (`sn_context_suffix`); same for
  the k8s and service-mapping context files. Demo1's file was regenerated by a no-op
  Demo1 deploy run.
- **Demo3 SGC takeover (approved by Gary 2026-11-23).** Before-state saved in
  `specifications/servicenow/docs/demo3_sgc_pre_takeover_snapshot.json` (no secrets; the
  old "Dynatrace API Key" value is unreadable and cannot be restored). Changes:
  - minted Dynatrace token `dynatrace-servicenow-sgc-integration-demo3` into
    "Dynatrace API Key";
  - "Dynatrace Connection" host `mjm80413.live.dynatrace.com` → `pdt20158.live.dynatrace.com`;
  - SGC connection row and `sn_dynatrace_integ.management_zone_*` → Spark Observability MZ;
    `service_types_to_ingest` set;
  - "SGO-Dynatrace Hosts" reactivated (daily); "SGO-Dynatrace Kubernetes Cluster" set to hourly;
  - `sn_dynatrace_integ.events_for_unmatched_ci.enabled` → true (was false);
  - Dynatrace notification `ServiceNow brooks-lab (demo3) - Spark Observability` created
    (SGO-Dynatrace endpoint, `admin_brooks_lab` auth, same alerting profile as Demo1).
- **start.yml took the previous import batch for the new one (fixed).** The poll for the
  new concurrent import set used `sys_created_on>=` the newest existing set, so the old
  set matched immediately. The playbook then restored the daily cadence before the
  scheduler ran, and no import happened. It is now a strict `>`.
- **start.yml Execute Now time was local, not UTC (fixed).** `run_start` was built with
  `strftime` in Lab3's local time (CST), but Table API date-times are UTC, so the run was
  queued 6 h in the past and never fired. It now uses `utc=True`.
- **Demo3's "Dynatrace Connection" was pinned to MID `DevMidServer` (Down)** — every
  import was cancelled with "no valid MID is available". Demo1's connection runs without a
  MID. `ensure_sgc_credential.yml` now enforces `use_mid=false` along with the hostname.
  After that, the first Demo3 import completed: 43 import sets processed, 11/11 lab feeds,
  no errors; `lab1`–`lab3` are in Demo3's CMDB (location empty until `discover.yml` runs on
  Demo3). "SGO-Dynatrace Hosts" now runs on the repo's canonical cadence (hourly), not the
  previous daily.
- **End to end:** stress-test problems P-26115909/10/11 were processed on **both** Demo1 and
  Demo3 at 19:35:11 UTC.
- **Stress test 3×2 (2026-11-23 19:31–20:41 UTC):** `run-stress.sh -p 3 -i 2`; all six
  thread-iterations rc=0 (66–70 min per thread). Each iteration logged the usual
  `FAILED_READ_FILE` WARN on `shows-silicon-valley.json` (task retried; chapter completed).
  Dynatrace → ServiceNow:
  | | Demo1 | Demo3 |
  | --- | --- | --- |
  | Problems received | 17 | 17 (same set) |
  | Events (all Processed) | 34 | 34 |
  | Events bound to a CI | 34 | 8 |
  | Alerts / with CI / with incident | 21 / 21 / 4 | 36 / 31 / 0 |
  | Alert CIs | Spark Client, spark-worker-lab1/2, lab1/2, brooks-lab | lab1–lab3 only |
  Delivery to both instances is complete. Demo3 binds only to hosts and raises no
  incidents because the CSDM / service-mapping / incident layers (step 13) have not been
  deployed there.
- **Step 13 (2026-11-23):**
  - Service Mapping prerequisites were already on Demo3: `sn_service_mapping` 23.1.3,
    `sn_itom_map_app`, `sn_itom_pattern`, `sn_cmdb_ci_class` and the
    `com.snc.service-mapping` plugin.
  - `service-mapping/deploy.yml` created the global Scripted REST API "Service Mapping
    Operations API" (`/api/opti8/service_mapping_operations_api`) and the
    "Service Instance" CI tag category. carl.marais's "Environment Key" and
    "Application Key" categories were left untouched. URIs are in
    `vars/contexts/servicenow_sm_deploy_demo3.json`. Demo1's file is unchanged.
  - `csdm/diagnose.yml` on Demo3: all 89 spec objects and relationships are
    missing. There are no name collisions, so the inject only adds records.
  - `sn-sync-inject` stopped on the first record, before any write:
    `sys_user user_name='gbrooks' not found`. 40 `owned_by` / `business_owner` /
    `it_application_owner` fields in the brooks-lab specs name `gbrooks`, and that
    user doesn't exist on Demo3.
  - **Resolved:**
    - Gary asked for a `gbrooks` on Demo3 cloned from the Demo3 account for
      `gbrooks@optimiz.ca`. The request named `gxbrooks@optimiz.ca`, but no such user
      exists; `gbrooks@optimiz.ca` is the only match. Gary maps `gxbrooks` on Demo1
      to that account.
    - Created `sys_user` `gbrooks`: same email, time zone, notification and
      calendar settings and identity type.
    - It has the same 9 direct roles: `admin`, `evt_mgmt_admin`, `evt_mgmt_operator`,
      `evt_mgmt_user`, `evt_mgmt_integration`, and `evt_mgmt_connector_instance_*`
      (create, read, write, delete).
    - The platform added the group "Conditional Script Writer" itself.
    - Not copied: `federated_id` (the SSO identity) and any password. The account
      has no password.
  - CSDM deploy, re-run:
    - `sn-sync-inject` created all 43 objects and their relationships on Demo3.
    - The horizontal-Discovery trigger then failed on a missing `sn_api_headers` in
      `csdm/common/vars.yml`. That bug also affects Demo1. It is fixed, and the re-run
      passes: DIS0015751 started.
  - `csdm/diagnose.yml` on Demo3 after the deploy:
    - All objects and relationships match.
    - Tag-based service maps are still `[empty]`, waiting for Discovery and
      Service Mapping.
    - `process_status` drifts on the two non-tag service instances, Spark Client and
      Dynatrace Tenant: expected `operational`, actual `2`. Demo3 (Australia) appears
      to store this choice differently from Demo1 (Zurich). Still open.
  - The incident deploy is held. Demo3 Event Management is in active use by others:
    1,975 alerts from source `Dynatrace` and 21 `Group Alert` alerts in the last
    30 days. `incident/deploy.yml` would change behaviour for everyone:
    - set `evt_mgmt.avoid_int_enabled` false→true;
    - set `sn_em_ai.evt_mgmt.disable_lists_auto_refresh` false→true;
    - change the Automated grouping `sa_analytics.agg.*` properties;
    - activate OOTB "Create Incident for Primary Alert" for all Group Alerts (it is
      inactive today);
    - overwrite the OOTB Script Include `EvtMgmtCustomIncidentPopulator` (unchanged
      since 2016);
    - add an Affected-CIs maintenance rule.
    The SGO-Dynatrace AMR (already active) and our enrich business rules are scoped to
    `SGO-Dynatrace`, which only brooks-lab feeds since the takeover.
- **Lab3 capacity:** ~34 GiB RAM available and 246 GB disk free, so a second MID
  fits.

## Open items (2026-11-23)

1. **Incident rules on Demo3.** Decide whether the instance-wide Event Management
   changes in `incident/deploy.yml` are acceptable on shared Demo3 (see step 13
   findings). If they are, set `SN_INSTANCES.demo3.incident_deploy_enabled: true`.
   Alternatively, split the playbook so that only the `SGO-Dynatrace`-scoped parts run
   there.
2. **`process_status` drift** on Demo3's Spark Client and Dynatrace Tenant (see
   step 13 findings).
3. **Non-Ansible readers** (`create-sn-change-window.py`, `servicenow/comparator`)
   still use `SN_URL`, so they act on Demo1 only.
4. **First `discover.yml` on Demo3**, so the lab hosts get the brooks-lab location.

## Risks / open questions

- **Demo3 SaaS connector state.** The half-installed "SGC for Dynatrace SaaS" may
  conflict with installing the legacy `sn_dynatrace_integ`, for example through a
  shared `SGO-Dynatrace` event source or scope. Check what is installed before installing.
- **Store entitlement.** On Demo1, App Manager installs of this app failed with
  `id: null`, likely a licence or entitlement problem. Demo3 may hit the same thing, so
  a manual UI install may be needed.
- **Shared Demo3.** Others use it: everything brooks-lab creates stays scoped by name
  (`brooks-lab` location, `brooks-lab` notification names).
