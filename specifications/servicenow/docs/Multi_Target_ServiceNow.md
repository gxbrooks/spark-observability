# Multi-target ServiceNow: one active instance at a time

Living doc. Started 2026-11-24. It replaces the concurrent-instance plan
(`Multi_Instance_Plan.md`, retired 2026-11-24).

## Goal

brooks-lab can feed either **optimizincdemo1** (Demo1, Zurich) or
**optimizincdemo3** (Demo3, Australia patch5b), but only **one at a time**.
The instance brooks-lab currently feeds is the **active instance**. Every
lab-side component points at it:

- the Lab3 MID Server;
- the Kubernetes KVA informer on the brooks-lab cluster;
- the Dynatrace problem notification;
- the Spark change-window script and the CMDB/Dynatrace comparator.

The other instance keeps its configuration, and none of it affects the active
instance.

### Why not both at once

- **K8s:** the ServiceNow KVA informer is one Helm release per cluster
  (`k8s-informer-<cluster>`), and its `instance.name` value names one instance.
- **MID Server:** the vendor MID `.deb` is one `agent` package with one install
  path (`/opt/servicenow/mid/agent`).
  - On 2026-11-23 a second MID was copied out of the `.deb` into its own
    directory (`/opt/servicenow/mid-demo3`), and both ran.
  - That layout is unsupported: the vendor uninstaller and auto-upgrade
    assume the package path. It is retired; Lab3 runs **one** MID.
- **Dynatrace:** problem notifications could feed both instances. They follow
  the active instance so problems go only where the MID and KVA data go.

## Model

### Target flag

Every ServiceNow playbook takes `-e target=<id>`, with `demo1` or `demo3` from
`SN_INSTANCES` in `vars/variables.yaml`. `target=all` is rejected. Without
`-e target`, a playbook uses the active instance (see the modes below for what
happens when there is none).

### The active instance is derived, never recorded

Nothing stores which instance is active (`servicenow_active_instance.yml` and
`SN_DEFAULT_TARGET` were removed 2026-11-24). Every run reads the live
components and derives it (`tasks/derive-active-instance.yml`):

| Component | Read from | Belongs to X when |
| --- | --- | --- |
| Lab3 MID Server | `/opt/servicenow/mid/agent/config.xml` `url`, `systemctl is-active mid_brooks_lab3` | `url` is X's URL and the service runs; no other MID tree or unit on the host |
| Dynatrace | `builtin:problem.notifications` `enabled` of the brooks-lab notification of each instance (`dt_problem_notification_name`) | X's notification is the **only** brooks-lab one enabled |
| KVA informer | `helm get values k8s-informer-brooks-lab` `instance.name`, deployment replicas | not installed, parked (0 replicas), or `instance.name` is X's |

X is **active** when all three agree. Otherwise no instance is active and the
run lists the inconsistencies, for example:

- `Lab3 MID Server: belongs to demo1 but its service is stopped`
- `Dynatrace: no brooks-lab problem notification is enabled (no instance receives events)`
- `Dynatrace: events go to demo3 but the MID Server belongs to demo1`
- `KVA informer: feeds demo3 but the MID Server belongs to demo1`

`playbooks/servicenow/diagnose.yml` is the consistency check: it reports every
component, runs its other checks, and **fails** at its end when no instance is
fully active. (A separate `status.yml` existed briefly; the automation standard
forbids that name, so its check moved into `diagnose.yml`.)

Every playbook prints the derivation first, for example:

```
Active ServiceNow instance: demo1
Lab3 MID Server: demo1, running
Dynatrace brooks-lab notifications: demo1 enabled, demo3 disabled
KVA informer: demo1, running
```

The Python tools (`spark/.../create-sn-change-window.py`,
`servicenow/comparator`) can't reach the MID or the cluster, so they use the
Dynatrace signal alone (`servicenow/sn_active_instance.py`): the instance whose
brooks-lab notification is the only one enabled. `SN_TARGET=<id>` overrides it.
They fail when no instance, or more than one, is enabled.

### Guard: `playbooks/servicenow/tasks/target.yml`

Every ServiceNow playbook imports `tasks/target.yml` first, with a **mode**
that depends on its verb:

| Mode | Playbooks | Target without `-e target` | When no instance is active |
| --- | --- | --- | --- |
| `switch` | every `install.yml`, `deploy.yml`, `start.yml` (including the sub-playbooks of `discovery/`, `discovery/k8s/`, `discovery/docker/`, `cmdb/`, `csdm/`, `service-mapping/`, `sgc/`, `sgc/sources/dynatrace/`, `events/`, `incident/`) | the active instance, else the MID's owner (e.g. after `stop.yml`) | Switches the lab to the target (procedure below), which makes it active. |
| `active` | every `test.yml` | the active instance | **Fails** with the inconsistencies and the `start.yml` command. Also fails when `-e target` names a non-active instance. |
| `any` | every `diagnose.yml`, `csdm/undeploy.yml`, `stop.yml`, `discovery/stop.yml` | the active instance, else the MID's owner | Reports the inconsistencies as an **ERROR** (ignored) and continues. Notes when the target is not the active instance. The top-level `servicenow/diagnose.yml` **fails** at its end with the inconsistencies. |

The guard runs once per `ansible-playbook` run. Guards in nested imports and
aggregators (`servicenow/deploy.yml`, whole-lab `playbooks/deploy.yml`) reuse
the first result.

### Switch procedure (mode `switch`, target A)

The steps run in this order. Every step is idempotent; when everything already
points at A, nothing changes.

1. **Dynatrace:** disable the brooks-lab problem notification of every instance
   other than A. Only the notifications named in `SN_INSTANCES`
   (`dt_problem_notification_name`) are touched.
2. **Lab3 MID Server** (`tasks/activate-mid-server.yml`):
   - **Another instance owns the MID: reconfigure it**
     (`discovery/tasks/reconfigure-mid-server.yml`). Stop the service, back up
     `config.xml`, then set A's `url`, `mid.instance.username`,
     `mid.instance.password` (plain text; the MID encrypts it on start) and
     `name` (A's `mid_server_name`), and drop `mid_sys_id`. Start the service.
     The MID finds its `ecc_agent` record on A by name and **auto-upgrades to
     A's build** (Zurich ↔ Australia).
   - **No MID on Lab3:** install A's `.deb` (`mid_installer_deb_url`), cached in
     `/var/cache/servicenow-mid/`.
   - **Fallback:** `-e sn_mid_switch_method=reinstall` uninstalls the MID and
     installs A's `.deb` instead of reconfiguring.
   - **A already owns it:** remove any extra MID trees or units, and make sure
     the service is enabled and running.
3. **KVA informer** (when the Helm release exists):
   - A has the Kubernetes Visibility Agent app (`sn_acc_visibility`): if
     `instance.name` is not A's, or the informer is parked, run `helm upgrade`
     with A's instance and credentials secret;
   - A lacks the app: **park** the informer (scale to 0 replicas) so it feeds
     no instance;
   - delete the other instances' `k8s-informer-cred-<short_name>` secrets.
4. **MID up, keys, validation:** wait until A's `ecc_agent` record is Up **on
   A's build**: its `version` must equal A's `mid.version` sys_property. A
   reconfigured MID first shows Up on its old build, then upgrades or downgrades.
   The wait allows 20 minutes. Then make sure A accepts the MID's keys (next
   section), and that the MID is validated.
5. **Dynatrace:** enable A's problem notification.
   - If it doesn't exist yet, `sgc/sources/dynatrace/events/deploy.yml` creates
     it, already enabled.
   - Enable and disable send the stored object back with only `enabled`
     changed. Dynatrace keeps the masked webhook secret.

### MID keys: RSA key and ECC signing key

Each `ecc_agent` record holds two of the MID's keys: its RSA public key
(`ecc_agent.public_key`) and an ECC signing key (table `ecc_agent_signing_key`,
on **both** Demo1/Zurich and Demo3/Australia). After an owner change, the
target instance still holds the keys of an earlier install, and the MID's one
keystore doesn't match them. Symptoms seen on 2026-11-24:

- RSA: `UpdatePublicKey error: New public key cannot be verified. MID Server
  encryption keys do not match`. The MID logs "MID server is not yet
  validated" even while the record says `validated=true`.
- ECC: the MID registers its own signing key only when the instance has **no**
  active or `pre_activation` key (`mid_ecc_signing_api`). When the instance
  holds a stale active key, the MID never registers. Earlier, HTTP 400 "No
  signing keypair found" was logged when a registration was refused.

Rules read from the instances (business rules, `MIDServerManage`, the signing
API):

- the instance accepts a changed RSA key only when `validated` is `false` or
  `rekey`. With `rekey`, the OOTB rule "MID rekey set validated true" accepts
  it and sets `validated=true`. This is what the OOTB **Rekey** UI action does.
- a signing-key registration from a validated MID, with a proof signed by its
  RSA key, becomes `active`. Otherwise it is `pre_activation`, and the next
  restart of the validated MID promotes it.
- setting `validated=true` by REST alone fixes neither key. It left Demo1's key
  in `pre_activation` for hours.

`tasks/ensure-mid-signing-key.yml` runs on every switch. It does the
OOTB rekey when the owner changed, when the newest signing key isn't active, or
when the MID's log since its last start shows a refused key or "not yet
validated":

1. deactivate the agent's active and `pre_activation` signing keys on the
   target;
2. set `validated=rekey`;
3. restart the MID, which pushes its RSA key and registers a signing key;
4. wait for `validated=true` and the new key (matched by sys_id, not by date:
   encoded-query date literals depend on the user's time zone);
5. restart once more if the key is `pre_activation`;
6. wait for `active`.

Both instances now hold the same keystore's keys, so later switches between
them need no rekey. Today's last two switches confirmed that.

### MID auto-upgrade needs a polkit rule

The MID upgrader runs as `servicenow-mid` and restarts its unit with plain
`systemctl start|stop|restart mid_brooks_lab3` (`bin/mid.sh`), **without sudo**.
Without a polkit grant, systemd refuses ("Interactive authentication
required"). The upgrader then gives up with `UpgradeStatus=rollback_failure`
and leaves the MID stopped, and auto-upgrade stays off until the next restart.
That happened on Lab3 on 2026-11-24. The repo's sudoers rule
(`/etc/sudoers.d/servicenow-mid`) never applied because sudo isn't used.
`discovery/tasks/ensure-mid-service-control.yml` now installs
`/etc/polkit-1/rules.d/50-servicenow-mid.rules`: user `servicenow-mid`, unit
`mid_brooks_lab3.service`, verbs start, stop and restart only, from the
representation `specifications/servicenow/integrations/discovery/mid-server-service-control.rules.j2`.
Install and every switch apply it. (The obsolete sudoers file was removed once
on Lab3; that cleanup isn't kept in the playbooks.)

## Verb analysis

The table covers target **A** while instance **B** is, or may be, active.

| Verb | B active, target A | A already active | Effect on B |
| --- | --- | --- | --- |
| **install** | Switch to A (steps 1–5), then install A's prerequisites: Discovery users, SGC / Service Mapping Store apps, KVA informer on A. | Ensure the MID is running; install whatever is missing. | B's notification disabled; the MID reconfigured away from B (B's `ecc_agent` record shows Down); KVA repointed to A or parked. B's apps and config stay. |
| **deploy** | Switch to A, then deploy A's instance-side configuration: Discovery, K8s/Docker CMDB, CMDB, SGC, events/notification, CSDM, Service Mapping, **incident rules**. | Re-apply A's configuration (idempotent). | As for install. |
| **start** | Switch to A, start the MID, and run the SGC Hosts import on A. | Start the MID and the KVA informer (after `stop`), re-enable A's notification, run the import. | As for install. |
| **stop** | Target A is not active: the MID and KVA belong to B and keep running; A's notification is already disabled. Nothing changes. | Stop the MID, park the KVA informer and disable A's notification. Afterwards no instance is active; `start.yml` (no target) resumes A, the MID's owner. | — |
| **discover / test / sync** | Refused: "target A is not active", with the switch command. | Run against A. | — |
| **diagnose** | Allowed (read-only), with a "not active" note. On the inactive instance, the MID and event checks report Down or old. | Run against A. | — |
| **csdm/delete** | Allowed: cleaning up the inactive instance is legitimate. | Run against A. | — |
| **status** | Reports each component and the inconsistencies; fails when no instance is fully active. | Reports A active. | — |

### What stays on the inactive instance

| Left in place on B | Impact on A |
| --- | --- |
| Discovery location, schedule, credentials, REST API | None. B's schedule finds its MID Down and does nothing. |
| CMDB / CSDM / Service Mapping objects, tag categories | None (separate instance). |
| SGC connection, credential and scheduled imports (they pull from Dynatrace) | None on A: separate Dynatrace tokens (`dt_sgc_api_token_name`), read-only Dynatrace API calls. B's CMDB keeps refreshing hosts. |
| Webhook user and roles for `SN_DT_WEBHOOK_*` | None. B's notification is disabled, so nothing posts. |
| `ecc_agent` record of B's MID (Down) and its signing keys | None. |
| Incident rules and the instance-wide Event Management settings `incident/deploy.yml` made | None on A. No brooks-lab events reach B, so they create no brooks-lab incidents there. |
| B's Dynatrace problem notification (disabled) | None. |

Things that would affect A are switched rather than left behind: the MID on
Lab3, the KVA informer, the notifications, and the tools that read the active
instance.

## Components that point at a ServiceNow instance

| Component | Where | Instance-specific setting | How it follows the active instance |
| --- | --- | --- | --- |
| MID Server | Lab3, `/opt/servicenow/mid/agent`, unit `mid_brooks_lab3` | `config.xml` `url`, `mid.instance.username` / `mid.instance.password` (`SN_MID_USER<suffix>`), `name` (`mid_server_name`: `mid-brooks-lab3` or `mid-brooks-lab3-demo3`); the build follows the instance by auto-upgrade | Reconfigured on switch (step 2). |
| KVA informer | K8s cluster `brooks-lab` (Lab1–3), namespace `servicenow-kva`, release `k8s-informer-brooks-lab` | Helm `instance.name` (`short_name`), secret `k8s-informer-cred-<short_name>` (`SN_USER<suffix>`); needs the Kubernetes Visibility Agent app on the instance | `helm upgrade`, or parked when the instance lacks the app (step 3). |
| Dynatrace problem notification | Dynatrace tenant, `builtin:problem.notifications` | One per instance (`dt_problem_notification_name`); webhook URL to the instance's OOTB `SGO-Dynatrace` push connector; `Authorization` header from `SN_DT_WEBHOOK_*<suffix>` | `enabled` flag (steps 1 and 5). Both use the same brooks-lab alerting profile. |
| SGC topology pull | On the instance (scheduled imports) with a Dynatrace API token per instance (`dt_sgc_api_token_name`) | The instance's own credential record | Not switched (instance side, no impact on the other). |
| Spark change windows | `spark/apps/data-analysis-book/bin/create-sn-change-window.py` (stress runs) | URL and `SN_USER<suffix>` / `SN_PASSWORD<suffix>` | Derives the active instance from the Dynatrace notifications; `--close` uses the instance recorded in the run's `change-window.json`. |
| CMDB / Dynatrace comparator | `servicenow/comparator` | URL and credentials | Derives the active instance from the Dynatrace notifications. |
| Docker container and K8s label sync | Ansible pushes (`discovery/docker/deploy.yml`, `k8s/tasks/sync-pod-labels.yml`, `sync_tags.yml`) | Target instance's REST API | Run against the target (switch or active mode). |
| Ansible deploy facts | `vars/contexts/servicenow_*_deploy_<id>.json` | sys_ids per instance | Per instance; kept for both. |
| Secrets | `vars/secrets.yaml`, `servicenow.<KEY><secrets_suffix>` | `""` for Demo1, `_DEMO3` for Demo3 | Selected by target. |

Not instance-specific (unchanged by a switch):
- the Dynatrace management zone, alerting profile, OpenPipeline processors and
  anomaly detectors;
- OneAgent;
- the K8s pod labels;
- the Spark workloads.

### Event source: the OOTB SGO-Dynatrace push connector

Both brooks-lab notifications post to
`/api/sn_em_connector/em/inbound_event?source=SGO-Dynatrace`. That is the OOTB
push connector **Dynatrace Observability** (`sn_em_connector_listener`, source
`SGO-Dynatrace`, sys_id `b70d280e07032010b1306a77c4a9355e`, unmodified, from the
SGC app) on both instances. The legacy connectors (`source=dynatrace`: the
"Dynatrace Monitor Push Connector", Demo1's "Optimiz - Demo" and Demo3's
"Dynatrace RTR Legacy" instances) are used only by other teams'
notifications. The repo's legacy fallback (`dt_legacy_connector_sys_id`) was
removed on 2026-11-24, so `events/deploy.yml` now requires SGC on the target.

## Release and configuration differences

The goal is that a switch works the same whatever each instance runs. Known
differences and how they are absorbed:

| Difference | Demo1 | Demo3 | Handling |
| --- | --- | --- | --- |
| Platform release | Zurich (patch12a) | Australia (patch5b) | The MID auto-upgrades to the configured instance's build; the playbooks wait for Up. |
| MID build (`mid.version`) | `zurich-07-01-2025__patch12a…` | `australia-02-11-2026__patch5b…` | Auto-upgrade or downgrade after a reconfigure (about 1–3 minutes); the switch waits for this exact build. |
| MID RSA and signing keys | present | present | OOTB rekey in `ensure-mid-signing-key.yml` when the keys don't match. |
| Kubernetes Visibility Agent app (`sn_acc_visibility`) | 3.14.1 | 3.16.1 (installed 2026-11-25 by `discovery/k8s/install.yml`) | No version pin (each release offers a different latest); the informer chart (image `informer:2.3.0`) feeds both. A target without the app parks the informer. |
| Kubernetes cluster CI sources | KVA CI only (created first) | SGO-Dynatrace CI first, then KVA added a second (merged 2026-11-25) | Not a release difference: KVA identifies by `k8s_uid`, SGC by `name` + `cluster_resource_id`. `discovery/k8s/deploy.yml` sets both on the one cluster CI so either source matches it (see "Resolved 2026-11-25"). |
| `cmdb_ci_service_discovered.process_status` | `1` on two services | `2` (default) | Not a release difference (next section). |
| Event Management shared with other teams | lightly | heavily (1,975 `Dynatrace` alerts / 30 days) | `incident/deploy.yml` runs on whichever instance is active (hold lifted 2026-11-24). |

### CSDM `process_status` "drift" (resolved 2026-11-24)

`sn-sync` set `process_status = "operational"` on manual application services
and `sn-sync-diff` compared it. On **both** releases `process_status` is an
integer choice for Service Mapping's questionnaire workflow: `0` Data
Gathering, `1` Finished Questionnaire, `2` In Progress, `3` In Review, `4`
Rejected, `5` Approved. `"operational"` isn't a valid value. Demo1 ended up with
`1` on Spark Client and Dynatrace Tenant, and Demo3 with the default `2`. Neither
value means anything here. `sn-sync` (repo `sn-sync`, `injector.py` and
`diff.py`) now sets and compares only `service_status = operational`, which is
the field that marks a manual service operational. Demo1's stored `1` values
are harmless and were left alone.

## Commands

From `automation/ansible/`:

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/diagnose.yml
```

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/start.yml -e target=demo3
```

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/deploy.yml -e target=demo3
```

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/stop.yml
```

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/test.yml
```

- **diagnose.yml:** the active instance, each component, the
  inconsistencies, and every ServiceNow diagnostic; fails at its end when no
  instance is fully active.
- **start.yml -e target=demo3:** switch to Demo3, start the MID, run the SGC
  import. A quicker switch without the import: `discovery/start.yml -e target=<id>`.
- **deploy.yml -e target=demo3:** switch to Demo3 and deploy its configuration,
  incident rules included.
- **stop.yml:** stop feeding the active instance.
- **events/test.yml:** check events on the active instance.

## Instance notes

- **Demo3 SGC takeover:**
  - Approved by Gary on 2026-11-23.
  - The before-state is in `demo3_sgc_pre_takeover_snapshot.json` (no secrets).
  - Demo3's "Dynatrace Connection" points at `pdt20158` directly (`use_mid=false`).
  - The "SGO-Dynatrace Hosts" import runs hourly.
- **Incident rules on Demo3:** the hold was lifted on 2026-11-24 at Gary's
  direction. `incident/deploy.yml` runs on the active instance, whichever it
  is. It changes instance-wide settings, which stay after a switch away:
  - `evt_mgmt.avoid_int_enabled`;
  - `sn_em_ai.evt_mgmt.disable_lists_auto_refresh`;
  - Automated grouping (`sa_analytics.agg.*`);
  - the OOTB "Create Incident for Primary Alert" rule;
  - `EvtMgmtCustomIncidentPopulator`.
- **Demo3 owner user:** `gbrooks` exists on Demo3. It is a clone of the
  `gbrooks@optimiz.ca` account (same email, time zone and 9 direct roles),
  without the SSO `federated_id` or a password.
- **Other teams' Dynatrace notifications** are never modified:
  - `ServiceNow Demo 1 - Optimiz` (enabled, `DemoProfile - Optimiz`, Demo1
    legacy connector `source=dynatrace`);
  - `Legacy Demo 3` (enabled, `Otel Demo` profile, Demo3 legacy connector);
  - `ServiceNow optimiz demo3` (disabled).

  `ServiceNow Demo 1 - Optimiz` may deliver some problems to Demo1 under
  source `dynatrace` while Demo3 is active. brooks-lab's own path is
  `source=SGO-Dynatrace`, and the tests check only that source.

## Installs and how they are automated

Everything installed for the two-instance setup is backed by a playbook. None
of it is a Terraform fit except the Dynatrace notification, see below.

| Installed | Playbook | Terraform |
| --- | --- | --- |
| Kubernetes Visibility Agent Store app on the instance | `discovery/k8s/install.yml` (manifest `specifications/servicenow/integrations/discovery/store_apps.yml`) | No: a one-way Store install (CI/CD App Repo API, no uninstall API), procedural. |
| KVA informer Helm release, credentials secret | `discovery/k8s/install.yml`; repoint/park on every switch (`tasks/activate-kva-informer.yml`) | Possible (`helm_release`, like `dynatrace_k8s.tf`), but `instance.name` and the replica count follow the derived active instance and are flipped by the switch, so Terraform would fight it. Not added. |
| Lab3 MID Server (install, reconfigure, polkit rule) | `discovery/install.yml`, `tasks/activate-mid-server.yml`, `discovery/tasks/reconfigure-mid-server.yml`, `ensure-mid-service-control.yml` | No: host package install and config-file rewrite, followed by the MID's own auto-upgrade. |
| MID keys (rekey) | `tasks/ensure-mid-signing-key.yml` | No: a procedure (deactivate, set `validated=rekey`, restart, wait). |
| Incident rules and properties on Demo3 | `incident/deploy.yml` | No ServiceNow Terraform provider in this repo. |
| brooks-lab Dynatrace problem notification (one per instance) | `sgc/sources/dynatrace/events/deploy.yml` → `observability/dynatrace/tasks/apply_dt_problem_notification.yml` | **Ready, not added.** The body is now the representation `specifications/dynatrace/integrations/sgc-problem-notification.json.j2` in the shared `templatefile()` syntax (verified to render in Terraform). Adding a `dynatrace_generic_setting` per instance first needs (a) a shared backend with locking, now in place (`automation/terraform/backend.tf`, 2026-11-25; the webhook secret would then sit in that cluster Secret), (b) `enabled` driven by the active instance, which the switch flips, and (c) the cross-platform drift test (Idempotency statement 6). |

## Automation standard compliance (2026-11-25)

The ServiceNow automation now follows `standards/automation.md`:

| Statement | Change |
| --- | --- |
| Service-management 4/6/7/12 | Only verb names at a module's top level. `status.yml` merged into `diagnose.yml`. `csdm/delete.yml` → `undeploy.yml`; `discovery/host/sync_tags.yml` → `host/deploy.yml`; `discovery/docker/discover.yml` → `docker/start.yml`; `discovery/k8s/discover.yml` → `k8s/start.yml` (informer restart behind `--tags all,kva_resync`); `discovery/discover.yml` → `discovery/tasks/run-discovery-scan.yml`, run with `discovery/start.yml --tags discovery_scan`; `k8s/sync_pod_labels.yml` and `label_oneagent_pods.yml` → `k8s/tasks/`; `events/apply_openpipeline_only.yml` → `events/deploy.yml --tags openpipeline`. |
| Service-management 8/9 | New `discovery/k8s/stop.yml` (root `stop.yml` imports it; root `start.yml` imports `k8s/start.yml`) and `discovery/docker/diagnose.yml`. Configuration-only modules (cmdb, csdm, incident, service-mapping, sgc) have no start/stop (statement 11). |
| Task playbooks 2 | Every task file is kebab-case (92 renamed). |
| Common directory 2 | `common/target.yml` and `common/tasks/` → `servicenow/tasks/`; CMDB 360 properties and Discovery REST operations moved out of `common/vars.yml`. |
| Representations 1/2/7/8 | Records that were built inline now load files under `specifications/`: Discovery schedule, range, range item and location; the Docker, K8s and SGC location business rules; the Discovery and Service Mapping REST APIs and operations; incident business rules, sys_properties and AMR flow; the Dynatrace SGC token; the polkit rule; the brooks-lab Dynatrace notification. `compare/dynatrace-correlation.yaml` (a stale duplicate) deleted, `csdm/test/servicenow_insert.yaml` moved, the unused `mid-config.xml.j2` deleted. |
| Ephemeral 1 | Deploy no longer re-applies the retired `em-alert-create-log-incident` business rule (a one-time play sits in `incident/tmp/`); the sudoers cleanup and the legacy `/run` REST path are gone. |
| Idempotency 2/3/5 | Updates run only when the live record differs from its representation (shared `servicenow/tasks/record-drift.yml`, which reports the differing field names). A second `servicenow/deploy.yml` writes nothing except the SSH credential, whose key can't be read back; that re-send and the CMDB license activation request are announced. This found two real defects: the L2I job's `run_period` was stored as 0, and the schedule sent two fields that don't exist. |
| Idempotency 4 | Ansible and Terraform rendered the custom log source differently (`${0}` vs `0`). The template now uses Terraform's escape for a literal placeholder, which the shared renderer now supports; `terraform plan` shows no resource changes. |
| Diagnostic and test 1/4 | The `discovery`, `discovery/k8s`, `discovery/docker` and `events` diagnose playbooks run their test checks (reported, not fatal), shared through task files. |
| Terraform 1 | Shared Kubernetes backend with Lease locking (`automation/terraform/backend.tf`); a concurrent plan is refused. |

Not run live: `csdm/undeploy.yml` (it deletes CIs; syntax-checked only).

## Resolved 2026-11-25

- **Duplicate `brooks-lab` cluster CI on Demo3.** Cause: the two sources
  identify the cluster by different fields of the Kubernetes Cluster
  identification rule. KVA sets `k8s_uid`; the SGC Dynatrace import sets
  `name` + `cluster_resource_id`. Both hold the same cluster UID (the uid of
  namespace `kube-system`), but neither CI had the other's field, so the IRE
  couldn't match them. Demo3 got the SGC CI first (2026-11-23) and KVA added
  its own (2026-11-25); Demo1 has only the KVA CI. Fix:
  - one-time merge on Demo3 (ephemeral play in `tmp/`): the KVA CI's 115 child
    CIs and 116 relationships moved to the SGO-Dynatrace CI, which was kept
    (as requested), then the KVA CI was deleted;
  - `discovery/k8s/deploy.yml` now gives the cluster CI both identifiers
    (`tasks/align-k8s-cluster-identifiers.yml`, cluster UID read from the
    cluster), so KVA and SGC match the same CI on either instance, in either
    order. It warns, and patches nothing, when it finds more than one cluster
    CI. Applied on Demo1; Demo3's CI got both in the merge.
- **L2IProcessPendingAlerts job period on Demo3**: was 0, set to every minute
  by an ephemeral play (`1970-01-01 00:01:00`, the representation's value).
- **ActiveGate crash loop / DynaKube `Deploying`.** Cause: Lab3's containerd
  ran runc with the cgroupfs driver while the kubelet uses systemd.
  `k8s/install.yml` generated containerd's full config only when none existed;
  on Lab3, Docker's minimal `config.toml` already did, so the
  `SystemdCgroup = true` edit had nothing to change. The mismatch made the
  kubelet rebuild pod sandboxes again and again. kube-proxy had 6,441 restarts
  in 28 days, and the ActiveGate (on Lab3 since 2026-11-19) never became Ready.
  Fix:
  - `k8s/install.yml` adds the runc `SystemdCgroup = true` table when the
    config lacks the setting; applied to Lab3, containerd restarted;
  - `k8s/diagnose.yml` now reads containerd's effective config (`config dump`)
    and reports MATCH on all three nodes;
  - `observability/dynatrace/start.yml` now ensures the ActiveGate is Ready
    (`tasks/ensure-activegate-running.yml`: recreates a crash-looping pod once,
    waits, fails with pointers otherwise);
  - `observability/dynatrace/diagnose.yml` reports ActiveGate readiness and
    restarts.

  Result: DynaKube `Running`, ActiveGate 1/1 with no restarts, no sandbox rebuilds
  since the fix, and `terraform plan` checks all pass.

## Open items

- **Dynatrace platform token exposure (`DT_PLATFORM_TOKEN_GRAIL`, and
  `DT_PLATFORM_TOKEN`).** Read-only Grail access (see scopes below): a holder
  can read Dynatrace logs, metrics and entities (hostnames, application
  output), not change anything. `DT_PLATFORM_TOKEN` (`document:write`, used to
  publish DQL dashboards) can create and change Dynatrace documents.

  What actually uses `DT_PLATFORM_TOKEN_GRAIL` (checked 2026-11-25):
  - `observability/dynatrace/deploy.yml --tags probe_dql`
    (`tasks/probe_dql_dashboard_queries.yml`) runs the dashboard tiles' DQL
    against `query:execute`: `timeseries` over host/JVM/GPU metrics with
    `entityName()`. Needs `storage:metrics:read`, `storage:entities:read`,
    and for any `fetch logs`, `storage:logs:read` + `storage:buckets:read`
    (the list in `automation/docs/manual-steps.md`).
  - **Nothing on ServiceNow.** `ResolveApplicationService.si.js` only builds
    DQL *text* for the incident description ("no Grail fetch"); no script
    reads `spark.l2i.dt_platform_token`, and the script include no longer has
    the `@@DT_PLATFORM_TOKEN_GRAIL@@` placeholder the playbook substitutes.
    The token is pushed to ServiceNow without being used there.

  Exposures:
  1. *Transcript exposure.* 2026-11-24: `incident/deploy.yml` printed
     `spark.l2i.dt_platform_token` in clear text (the
     `cmdb/tasks/apply-sys-property.yml` report); values are now masked.
     2026-11-25: a replacement Grail token was pasted into the AI assistant's
     chat (exposed the same way, so **not** used), and an assistant search
     that did not exclude the gitignored worktree copy
     `.claude/worktrees/strange-murdock-ec58cb/vars/secrets.yaml` printed both
     `DT_PLATFORM_TOKEN` and `DT_PLATFORM_TOKEN_GRAIL` (same values as the main
     checkout). A token is clean only if it never passes through chat or
     command output.
  2. *Stored in plain text on ServiceNow (standing risk).* `incident/deploy.yml`
     writes the Grail token as a plain `string` sys_property on the active
     instance (Demo1; Demo3 since 2026-11-24, a shared instance). Anyone who
     can read `sys_properties` there can read it. Rotation does not fix this.
     Since nothing on ServiceNow uses it, the fix would be to stop pushing it
     and delete the property, rather than `password2`. **Decision
     (2026-11-25): keep pushing it for now** — an accepted, documented risk.
     Each rotation therefore also needs `incident/deploy.yml` on the active
     instance (the other instance keeps the revoked value until it is next
     active, which is harmless once revoked).

  To rotate (only in the Dynatrace account UI; platform tokens, `dt0s16…`,
  cannot be created or revoked by any API token here): revoke the current
  `DT_PLATFORM_TOKEN` and `DT_PLATFORM_TOKEN_GRAIL` and the Grail token pasted
  on 2026-11-25; create replacements (Grail: `storage:metrics:read`,
  `storage:entities:read`, `storage:logs:read`, `storage:buckets:read`;
  dashboards: `document:write`);
  put each in `vars/secrets.yaml` without it passing through chat:
  `python3 -I tmp/set_grail_token.py vars/secrets.yaml tmp` for the Grail
  token, then the same with a trailing `DT_PLATFORM_TOKEN` (reads it with no
  echo, edits the one line, backs up to `tmp/secrets.yaml.bak-<KEY>`). Update
  the worktree copy too, or delete that worktree. Validate with
  `observability/dynatrace/deploy.yml --tags probe_dql` (Grail) and
  `--tags dashboards` (document:write). Delete the `tmp/` backups once the new
  tokens work.

- **AKS OTel demo cluster** (`aks-otel-demo` in `K8S_CLUSTERS`, Braden's
  cluster): not managed by this repo, and there is no kube context for it here.
  It has no `kva_informer` flag. Enabling KVA there needs its kubeconfig and
  owner's agreement. A KVA informer per cluster follows the same rule: one
  instance per informer.

## Test log

### Round 4: full Demo3 run after the compliance refactor (2026-11-25 afternoon)

- `servicenow/diagnose.yml`: "Active ServiceNow instance: demo1".
- `servicenow/deploy.yml -e target=demo3`: switched Demo1 → Demo3 (MID
  repointed and rekeyed, KVA informer repointed, notifications swapped) and
  deployed every module. The only changes were the switch itself; no
  configuration drift on Demo3. One `brooks-lab` cluster CI, with the cluster
  UID.
- `discovery/test`, `discovery/k8s/test`, `discovery/docker/test` and
  `servicenow/diagnose.yml`: passed.
- `events/test` and `incident/test` first failed: no SGO-Dynatrace events yet
  on the just-activated instance. After one stress iteration
  (`run-stress.sh -p 1 -i 1`, 12 minutes) both passed (15 events; 8 log
  alerts checked, none closed while their incident is active, no split
  groups).
- A second `servicenow/deploy.yml -e target=demo3`: `changed=0`.
- Switched back to Demo1 (`discovery/start.yml -e target=demo1`);
  `servicenow/diagnose.yml` passed with "Active ServiceNow instance: demo1".

### Round 3: KVA app on Demo3, standard compliance (2026-11-25)

- `sgc/sources/dynatrace/events/deploy.yml` on Demo1 with the notification body
  moved to its representation file: the first runs renamed the Demo1
  notification to the literal `{{ sn_instance_cfg.dt_problem_notification_name }}`
  and then created a duplicate. Cause: the `tf_template` lookup reads play
  variables raw. Fixed by passing every value as a lookup keyword argument.
  Repaired with an ephemeral play in `tmp/` (deleted exactly the two broken
  objects; the next deploy recreated the notification). No events were lost.
  The broken copies still posted to Demo1, so some events may have been
  duplicated. Re-run: no create, no update (the whole-value compare matches).
- `discovery/k8s/install.yml -e target=demo3`: switched Demo1 → Demo3
  (reconfigure, upgrade to Australia, rekey, informer parked), then installed
  `sn_acc_visibility` 3.16.1 on Demo3 through the CI/CD App Repo API ("CI/CD
  operation: successful"), then repointed the informer
  (`k8s-informer-optimizincdemo3`, Running).
- `discovery/k8s/deploy.yml` then `test.yml` on Demo3: the first test failed
  with "Cluster brooks-lab location is not brooks-lab": deploy had run before
  the informer created the cluster CI. Re-running deploy, then test, passed: 3 nodes,
  46 pods, 10 deployments, 14 services. Two cluster CIs (see "Open items").
- `servicenow/diagnose.yml` on Demo3 (guard moved to `tasks/target.yml`):
  passed; verdict "Active ServiceNow instance: demo3".

### Round 2: derived active instance, MID reconfigure (2026-11-24 afternoon)

**MID auto-upgrade stuck (found and fixed).** The first KVA install run timed
out waiting for a signing key while the MID was upgrading. The upgrader had
installed patch12a and then failed to restart the unit 38 times ("Interactive
authentication required"), ending with `rollback_failure`. A leftover upgrader
from 10:31 was still in the unit's cgroup. Fix: the polkit rule above; the
leftover process was killed. After a restart the MID upgraded and restarted
itself in about 1 minute (`start.sh` ExitCode=0).

**KVA informer installed** on brooks-lab (`discovery/k8s/install.yml`,
Demo1). Its first steps rekeyed Demo1, whose key had been `pre_activation`
since 16:37: the key went to active, and the old one was suspended.
`discovery/k8s/test.yml` passed: cluster `brooks-lab` (a single CI, no duplicate
with SGO-Dynatrace), 3 nodes, 10 namespaces, 10 deployments, 46 pods.

**Switch to Demo3** (`discovery/start.yml -e target=demo3`, 4 minutes):
- MID reconfigured (not reinstalled), then upgraded Zurich → Australia in about
  1 minute;
- KVA parked (Demo3 has no KVA app);
- Demo1's notification disabled and Demo3's enabled.

The MID then showed the RSA and signing-key mismatch. The OOTB rekey fixed it:
new key active at 21:31:30, "not yet validated" gone. A re-run was idempotent
(`changed=0`).

**Incident rules on Demo3.** `incident/deploy.yml` created or updated 6
properties on Demo3. A stress run (`run-stress.sh -p 1 -i 1`) delivered
SGO-Dynatrace events to Demo3 from 21:32, all Processed, with incidents on the
alerts (e.g. INC0010486 and INC0010487 for P-26116287 and P-26116286).
`events/test.yml` with no target resolved Demo3 and passed (8 events). With
`-e target=demo1` it was refused; `target=all` was refused.

**Switch back to Demo1** (during the stress run):
- the MID was reconfigured and downgraded Australia → Zurich patch12a;
- the KVA informer came back from parked;
- no rekey was needed: both instances now hold the MID's keys.

The first attempt failed because the MID showed Up on its old (Australia)
build just before the downgrade. The wait now requires `version ==
mid.version`. The re-run first reported "Active ServiceNow instance: NONE",
because no notification was enabled after the partial switch, then completed.
Events: Demo3's last was 21:42:53, before its notification was disabled at
about 21:43:16; Demo1's first was at 21:46:03, right after its notification
was enabled. `events/test.yml` passed on Demo1. Demo1's new alerts were grouped
under a group alert that has the incident.

**Stop and resume.**
- `stop.yml`: MID stopped, KVA parked, Demo1's notification disabled.
- `status.yml`: failed with 2 inconsistencies ("MID belongs to demo1 but is
  stopped", "no brooks-lab notification enabled").
- `discovery/diagnose.yml`: printed the ERROR (ignored) and continued against
  Demo1.
- `events/test.yml`: refused, with the `start.yml` command.
- `discovery/start.yml` with no target: resumed Demo1 (MID, KVA, notification).
- `status.yml`: passed.

The Python tools (change-window, comparator) derived Demo3, then Demo1.

**Not tested:** a whole-lab run; the full `servicenow/deploy.yml` and
`start.yml` aggregators across a switch (same guard); `-e
sn_mid_switch_method=reinstall`.

### Round 1: reinstall-based switching, recorded active instance (2026-11-24 morning, superseded)

Both directions worked by uninstalling and reinstalling the MID. Events
followed the active instance; Demo3 needed a manual invalidate → validate
re-key. The design changes since then: the active instance is derived instead
of recorded, the MID is reconfigured, the OOTB rekey is used, polkit was added,
and the KVA informer was installed.
