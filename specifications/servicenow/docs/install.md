# ServiceNow Discovery — installation guide

This document covers **prerequisites** on the ServiceNow instance and lab hosts,
then the Ansible install sequence for brooks-lab Discovery.

**Instances:** [https://optimizincdemo1.service-now.com/](https://optimizincdemo1.service-now.com/) (`demo1`, unsuffixed secrets);
[https://optimizincdemo3.service-now.com/](https://optimizincdemo3.service-now.com/) (`demo3`, `*_DEMO3` secrets).  
**Target:** brooks-lab feeds **one instance at a time** (the active instance). Every
ServiceNow playbook takes `-e target=demo1|demo3`; the default is the active instance,
which every run derives from the lab components (nothing records it). The commands in
this guide omit `target`, so they act on the active instance. Install, deploy and start playbooks with another target switch
the lab to it first. See [Multiple ServiceNow instances](#multiple-servicenow-instances).
Examples naming optimizincdemo1 record how Demo1 was set up; the same steps apply to each instance.  
**Playbooks:** `automation/ansible/playbooks/servicenow/discovery/`  
**Variables:** `vars/variables.yaml` → `**service-now`** context → generated
`vars/contexts/servicenow_ansible_vars.yml`  
**Secrets:** `vars/secrets.yaml` → `servicenow:` block (see `vars/secrets.example.yaml`)

---

## Prerequisites overview

Sections **1–4** are **Phase 1** (horizontal Discovery). Sections **5–7** are Phases **2–4**
(Kubernetes KVA, Docker container discovery, Dynatrace SGC).

Phase 1 needs **three separate identities**. They must not be combined into one
ServiceNow user.


| Identity             | Where it lives             | Purpose                                                     |
| -------------------- | -------------------------- | ----------------------------------------------------------- |
| **admin_brooks_lab** | ServiceNow (`SN_USER`)     | Ansible REST automation — locations, credentials, schedules |
| **mid_brooks_lab**   | ServiceNow (`SN_MID_USER`) | MID Server agent authentication only                        |
| **sn-discovery**     | Linux on Lab1–Lab3         | SSH target for Discovery classification probes              |


---

## 1. ServiceNow user: `admin_brooks_lab`

Used by Ansible `deploy.yml`, `discover.yml`, `diagnose.yml`, and `test.yml`.
Mapped to `servicenow.SN_USER` in `vars/secrets.yaml`.

### User record


| Field                  | Value                                              |
| ---------------------- | -------------------------------------------------- |
| **User ID**            | `admin_brooks_lab`                                 |
| **Identity type**      | Machine                                            |
| **Web service access** | Enabled (required for REST Table API / Basic Auth) |
| **Interactive login**  | Not required                                       |


### Required roles (minimum effective set)

Grant enough rights to **read and write** Discovery configuration tables and
CMDB locations. On optimizincdemo1 the following roles are effective:


| Role                                    | Why                                                                                                                                                                                                                                  |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **discovery_admin**                     | Discovery schedules, ranges, credentials, run scans *(or equivalent ACLs via elevated CMDB/admin roles)*                                                                                                                             |
| **cmdb_inst_admin**                     | Create/update `cmn_location` (**brooks-lab**); CMDB CI tables. For tag-based Service Mapping, also requires a **table ACL extension** on `**cmdb_key_value`** — see [§6.3](#63-enable-automation-to-update-key-value-pairs) |
| **rest_service**                        | REST API access                                                                                                                                                                                                                      |
| **snc_platform_rest_api_access**        | Table API authentication                                                                                                                                                                                                             |
| **cmdb_query_builder** or **cmdb_read** | `test.yml` CMDB validation                                                                                                                                                                                                           |


Additional roles on the demo instance (ITSM workspace, import, etc.) are fine
but not required for Phase 1.

### Must not use this user for

- MID Server `config.xml` authentication (`mid.instance.username`) — use
`mid_brooks_lab` instead.

### Secrets mapping

```yaml
servicenow:
  SN_USER: "admin_brooks_lab"
  SN_PASSWORD: "<machine-user password>"
```

---

## 2. ServiceNow user: `mid_brooks_lab`

Used **only** by the MID Server agent on Lab3 to poll the instance and execute
Discovery jobs from the ECC queue. Mapped to `servicenow.SN_MID_USER` /
`SN_MID_PASSWORD` in `vars/secrets.yaml`.

### User record


| Field                  | Value            |
| ---------------------- | ---------------- |
| **User ID**            | `mid_brooks_lab` |
| **Identity type**      | Machine          |
| **Web service access** | Enabled          |
| **Interactive login**  | Not required     |


### Required roles


| Role           | Required                   |
| -------------- | -------------------------- |
| **mid_server** | **Yes — only role needed** |


Do **not** grant `discovery_admin`, `admin`, or `itil` to this user unless
ServiceNow support documents a specific exception. Least privilege is
`mid_server` alone.

### Password and `config.xml`

`config.xml` is the **MID Server agent's own configuration file**. It is not a
file in this repository. Lab3 runs one MID, owned by the active instance, and its
file is `/opt/servicenow/mid/agent/config.xml` (owner `servicenow-mid`; read with
sudo). Its `url` names the instance that owns the MID.

See [One MID Server on Lab3](#one-mid-server-on-lab3-owned-by-the-active-instance).

The MID agent reads it at startup. The parameters that matter here:

| Parameter                 | Value                                         |
| ------------------------- | --------------------------------------------- |
| `url`                     | the instance, e.g. `https://optimizincdemo1.service-now.com` |
| `name`                    | `SN_INSTANCES.<id>.mid_server_name` (`mid-brooks-lab3`, `mid-brooks-lab3-demo3`) |
| `mid.instance.username`   | `mid_brooks_lab` (`SN_MID_USER<secrets_suffix>`) |
| `mid.instance.password`   | `SN_MID_PASSWORD<secrets_suffix>`              |

The ServiceNow `mid_brooks_lab` User ID and password must match the two
`mid.instance.*` values exactly.

**How the file is written:** `discovery/install.yml --tags mid_server [-e target=<id>]`
(`tasks/install-mid-server.yml`) installs the vendor `.deb` package into
`/opt/servicenow/mid/agent`. It then runs the vendor's
`installer.sh -silent -INSTANCE_URL … -MID_USERNAME … -MID_PASSWORD …` there,
and that script writes `config.xml`. The script only runs on a first install. To
rotate the password afterwards, edit `mid.instance.password` in that
`config.xml` with sudo, then restart the MID service `mid_brooks_lab3`
(`tasks/restart-mid-server.yml`). The agent encrypts the value on its next start.

On a switch to another instance, `discovery/tasks/reconfigure-mid-server.yml`
rewrites `url`, `name`, `mid.instance.username` and `mid.instance.password` in
the existing `config.xml` (and drops `mid_sys_id`); see
[One MID Server on Lab3](#one-mid-server-on-lab3-owned-by-the-active-instance).

When editing `config.xml` by hand, XML-escape `&`, `<`, `>`, and quotes in the
password (`&amp;` etc.). Prefer passwords without them.

### What the MID user cannot do (verified)

`mid_brooks_lab` with `**mid_server` only** is **not sufficient to complete
Phase 1 by itself**:


| Action                               | MID user | admin_brooks_lab |
| ------------------------------------ | -------- | ---------------- |
| Authenticate MID agent / ECC queue   | Yes      | N/A              |
| Read `ecc_agent` (MID registration)  | Yes      | Yes              |
| Create `cmn_location` (brooks-lab)   | **No**   | Yes              |
| Create `discovery_credentials`       | **No**   | Yes              |
| Create `discovery_schedule` / ranges | **No**   | Yes              |
| Run `deploy.yml` / `discover.yml`    | **No**   | Yes              |


**Conclusion:** Phase 1 requires **both** users — `admin_brooks_lab` for
Ansible instance configuration and `mid_brooks_lab` for the MID Server process.

### Secrets mapping

```yaml
servicenow:
  SN_MID_USER: "mid_brooks_lab"
  SN_MID_PASSWORD: "<machine-user password>"
```

---

## 3. Linux user: `sn-discovery` (lab hosts)

Not a ServiceNow account. Created on **Lab1, Lab2, and Lab3** by
`discovery/install.yml`.


| Field        | Value                                                              |
| ------------ | ------------------------------------------------------------------ |
| **Username** | `sn-discovery` (override: `SN_DISCOVERY_USER` in `variables.yaml`) |
| **Auth**     | SSH public key (generated on controller)                           |
| **Sudo**     | Limited NOPASSWD for Discovery classification commands             |
| **Purpose**  | Target credential for SSH-based Linux CI Discovery on lab servers  |


Private key path (gitignored): `vars/sn_discovery_id_ed25519`  
Uploaded to ServiceNow as credential `**brooks-lab-ssh`** by `deploy.yml`.

---

## 4. Instance and lab prerequisites

### ServiceNow instance

- ITOM **Discovery** and **CMDB** licensed/active on the instance
- `admin_brooks_lab` and `mid_brooks_lab` created with roles above
- `SN_URL` set in `vars/variables.yaml` (service-now context; not a secret)
- `vars/secrets.yaml` populated (both users, passwords)
- Copy `vars/secrets.example.yaml` field names if migrating from older `lab_admin` naming

### Lab hosts

- Lab1, Lab2, Lab3 powered on and reachable via Ansible inventory
- Lab3 outbound HTTPS (443) to every instance in `SN_INSTANCES` (`optimizincdemo1.service-now.com`, `optimizincdemo3.service-now.com`) and to `install.service-now.com` (MID auto-upgrade packages)
- Lab3 can reach `192.168.1.0/24` for Discovery scans
- ~4–6 GiB RAM headroom on Lab3 for MID JVM (see `docs/architecture-and-resources.md`)

### MID Server package

- `SN_INSTANCES.<id>.mid_installer_deb_url` in `vars/variables.yaml` (service-now context)
points at the Linux `.deb` that matches the **instance build**. It is used only
when Lab3 has no MID (or with `-e sn_mid_switch_method=reinstall`); a switch
reconfigures the existing MID, which then auto-upgrades to the instance's build.

**Current value (optimizincdemo1, Zurich build
`glide-zurich-07-01-2025__patch7b-hotfix1-05-18-2026_05-19-2026_0833`):**

```
https://install.service-now.com/glide/distribution/builds/package/app-signed/mid-linux-installer/2026/05/19/mid-linux-installer.zurich-07-01-2025__patch7b-hotfix1-05-18-2026_05-19-2026_0833.linux.x86-64.deb
```

**How to find the URL when the instance is upgraded:**

1. In ServiceNow: **MID Server > Downloads** (or **All > MID Server > Downloads**).
2. Select the Linux installer for your instance version.
3. Copy the signed `.deb` URL, or read `glide.war` from the instance and match
  the build string in the filename.
4. Update `SN_INSTANCES.<id>.mid_installer_deb_url` in `variables.yaml` and re-run
  `discovery/install.yml --tags mid_server`.

The MID installer build **must** match the instance; a mismatch prevents the MID
from registering or causes ECC queue failures.

### brooks-lab Discovery scope (configured by `deploy.yml`)


| Object           | Name / value                                                                |
| ---------------- | --------------------------------------------------------------------------- |
| Location         | `brooks-lab` (`cmn_location`)                                               |
| IP range         | `192.168.1.0/24`                                                            |
| SSH credential   | `brooks-lab-ssh` → `sn-discovery`                                           |
| Schedule         | `Brooks Lab CI Discovery`                                                   |
| MID Server name  | `mid-brooks-lab3` (Lab3)                                                    |
| Discover Now API | **Discovery Operations API** (global Scripted REST; `discovery/deploy.yml`) |


Only Lab1–Lab3 have SSH credentials; other addresses on the subnet may appear
as network or unclassified devices.

### Discovery Operations REST API (`discovery/deploy.yml`)

`deploy.yml` creates a **global-scoped Scripted REST API** (**Discovery Operations
API**) that wraps the platform `global.Discovery()` scriptable API. `discover.yml`
calls the schedule endpoint; operators and automation may also call Quick Discovery.


| Endpoint                                  | Script API                  | Body (JSON)                              |
| ----------------------------------------- | --------------------------- | ---------------------------------------- |
| `POST …/schedule/run` | `discoverNow(scheduleGr)`   | `schedule_name` **or** `schedule_sys_id` |
| `POST …/quick/run`                        | `discoveryFromIP(ip, mid?)` | `ip_address`; optional `mid_server`      |



| Requirement                                     | Role                                                   |
| ----------------------------------------------- | ------------------------------------------------------ |
| Create `sys_ws_definition` / `sys_ws_operation` | `**web_service_admin`**                                |
| Execute Discovery in the script                 | `**discovery_admin**`                                  |
| Invoke the REST endpoint                        | `**rest_service**`, `**snc_platform_rest_api_access**` |


ServiceNow assigns the base path (instance-specific). Operation URIs are written
to `vars/contexts/servicenow_discovery_deploy_<id>.json` (one file per instance, e.g. `_demo1`, `_demo3`) as `discovery_rest_operation_uri`
and `discovery_rest_quick_uri`.

CMDB license checks use the **CI/CD plugin activate API** (`sn_cicd.sys_ci_automation`)
— not Table API reads on `sys_plugins`.

---

## 5. Phase 2 — Kubernetes prerequisites (KVA Informer)

Phase 2 discovers the brooks-lab Kubernetes cluster into CMDB via the **Kubernetes
Visibility Agent (KVA) Informer** only. Cluster identity is shared with Dynatrace
so CMDB and observability stay aligned on one **K8-native cluster name**.

### Variable model (`vars/variables.yaml`)

All Kubernetes cluster definitions live in the **Kubernetes** section of
`variables.yaml`. Use **K8-prefixed** names (not `SN_` or `DT_`) for constructs
that exist in the cluster itself.


| Variable                | Purpose                                                                                                                                                                                       |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `**K8S_CLUSTERS`**      | Multi-entry registry (list). Each entry describes one cluster known to the shared ServiceNow instance, with per-entry **capability flags** selecting what this repo's automation does for it. |
| `**K8S_KVA_HELM_REPO`** | ServiceNow KVA Informer Helm repository URL.                                                                                                                                                  |


Regenerate context files after editing:

```bash
generate-contexts --vars-dir ./vars service-now
# or: ansible-playbook ... discovery/tasks/regenerate-context.yml
```

Generated outputs: `vars/contexts/servicenow_ansible_vars.yml` (includes
`K8S_CLUSTERS`).

### `K8S_CLUSTERS` entry fields

Each list item in `K8S_CLUSTERS` supports:


| Field                    | Required            | Description                                                                                                                                                                                                             |
| ------------------------ | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `**name**`               | Yes                 | Kubernetes cluster name in CMDB and Dynatrace (must match KVA `clusterName`).                                                                                                                                           |
| `**location**`           | Yes                 | `cmn_location.name` in ServiceNow (`k8s/deploy.yml` creates location if missing). Every entry with a location is location-mapped, regardless of flags.                                                                  |
| `**location_full_name**` | Recommended         | Display name for `cmn_location` when created by deploy.                                                                                                                                                                 |
| `**kva_informer**`       | Capability flag     | `true` = this repo installs the KVA informer (`k8s/install.yml`) and validates the cluster's CMDB content (`k8s/test.yml`). Absent = false.                                                                             |
| `**dynatrace**`          | Capability flag     | `true` = this repo applies DynaKube, auto-tags, and the management zone for this cluster name (Dynatrace playbooks). Absent = false. Exactly one entry may carry this flag (templates reference a single cluster name). |
| `**kva_namespace**`      | When `kva_informer` | Namespace for KVA Informer (e.g. `servicenow-kva`).                                                                                                                                                                     |
| `**api_url**`            | Optional            | Kubernetes API URL (documentation / future use).                                                                                                                                                                        |
| `**environment**`        | Optional            | `on-prem`, `azure`, etc.                                                                                                                                                                                                |
| `**cloud_provider**`     | Optional            | Cloud provider when applicable.                                                                                                                                                                                         |


**Example (current optimizincdemo1):**

```yaml
K8S_CLUSTERS:
  value:
    - name: brooks-lab
      location: brooks-lab
      location_full_name: Brooks Lab
      kva_informer: true
      dynatrace: true
      api_url: https://192.168.1.207:6443
      kva_namespace: servicenow-kva
      environment: on-prem
    - name: aks-otel-demo
      location: bradens-cloud
      location_full_name: Braden Cloud Demo
      environment: azure
      cloud_provider: azure
  contexts: [service-now, dynatrace-ansible]
```

No ServiceNow custom mapping table is required. `K8S_CLUSTERS` is the GitOps
source; `k8s/deploy.yml` applies locations to cluster CIs and installs the
instance business rule that inherits `cluster.location` to child K8s CIs.
Entries without capability flags (e.g. `aks-otel-demo`) exist solely for
location mapping of CIs that arrive via someone else's instrumentation.

### Dynatrace alignment

The `dynatrace: true` entry's `name` replaces the former `DT_K8S_CLUSTER_NAME`
/ `K8S_PRIMARY_CLUSTER`. After changing the cluster name, redeploy Dynatrace
so DynaKube, auto-tags, and management zones match:

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/specifications/dynatrace/deploy.yml \
  -e @../vars/secrets.yaml --tags k8s,partitioning
```

### Phase 2 install sequence

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/install.yml \
  -e @../vars/secrets.yaml
# wait for KVA full discovery (~5 min)
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/deploy.yml \
  -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/k8s/test.yml \
  -e @../vars/secrets.yaml
```

See `discovery/k8s/README.md` for playbook details.

---

## 6. Phase 3 — Docker prerequisites

Phase 3 registers running Docker containers from Compose stacks into CMDB. Location is
inherited from the **Linux server CI** via an instance business rule — the same GitOps
pattern as Kubernetes.

### 6.1 Variable model (`vars/variables.yaml`)

Docker host definitions live in `**vars/variables.yaml`** (immediately after
`K8S_CLUSTERS`). Use **Docker-prefixed** names (not `SN_`) for host/stack constructs.


| Variable           | Purpose                                                                                                                                                          |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `**DOCKER_HOSTS`** | Multi-entry registry (list). Each entry describes one Docker host/stack, with a per-entry **capability flag** selecting what this repo's automation does for it. |


Regenerate context files after editing:

```bash
generate-contexts --vars-dir ./vars -f service-now
```

### 6.2 `DOCKER_HOSTS` entry fields


| Field                     | Required                   | Description                                                                                                                                                 |
| ------------------------- | -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `**name**`                | Yes                        | Logical stack name (used in playbooks and logs).                                                                                                            |
| `**location**`            | Yes                        | Expected `cmn_location.name` (inherited from host CI via business rule).                                                                                    |
| `**location_full_name**`  | Recommended                | Display name when location is created by deploy.                                                                                                            |
| `**container_discovery**` | Capability flag            | `true` = this repo syncs running containers into `cmdb_ci_docker_container` (`docker/start.yml`) and validates them (`docker/test.yml`). Absent = false. |
| `**cmdb_host_name**`      | Yes                        | CMDB Linux server name (e.g. `lab3` from Phase 1).                                                                                                          |
| `**ansible_host**`        | When `container_discovery` | Inventory host to run `docker ps` on (e.g. `Lab3`).                                                                                                         |
| `**compose_dir**`         | Optional                   | Compose project directory name (documentation).                                                                                                             |
| `**description**`         | Optional                   | Human-readable stack description.                                                                                                                           |


**Example (current optimizincdemo1):**

```yaml
DOCKER_HOSTS:
  value:
    - name: lab3-observability
      location: brooks-lab
      location_full_name: Brooks Lab
      container_discovery: true
      cmdb_host_name: lab3
      ansible_host: Lab3
      compose_dir: observability
      description: Lab3 observability Docker Compose stack
  contexts: [service-now, dynatrace-ansible]
```

Phase 1 must have discovered the host CI with the expected location before Phase 3.
`docker/deploy.yml` installs business rule `**docker-inherit-location-from-host**`
so new/updated `cmdb_ci_docker_container` rows copy `host.location`.

### 6.3 Enable automation to update key-value pairs

An out-of-the-box ServiceNow instance does not include permission configurations
sufficient for an automation service account (for example **`admin_brooks_lab`**) to
create tag key-value pairs. To enable automations to manage the **`cmdb_key_value`**
table, an authorized operational administrator must create the requisite ACLs. To
simplify configuration, augment the **`cmdb_inst_admin`** role with **create**,
**write**, and **delete** permissions on rows in **`cmdb_key_value`**. The procedure
below describes how to do so.

The automation service account (**`admin_brooks_lab`**) was assigned several roles —
see [§1 — Required roles](#required-roles-minimum-effective-set). One of those roles is
**`cmdb_inst_admin`**. Out of the box, **`cmdb_inst_admin`** can **read** the
**`cmdb_key_value`** table (via **`cmdb_read`** in the role hierarchy). Create Allow-if
ACLs only for **create**, **write**, and **delete**. Each ACL for **`cmdb_inst_admin`**
should use the fields in **Table 6.3 — `cmdb_key_value` ACL record fields**.

#### Table 6.3 — `cmdb_key_value` ACL record fields

| Field name | Value | Comment |
| ---------- | ----- | ------- |
| **Type** | `record` | Table ACL (not field or other type) |
| **Operation** | `create`, `write`, or `delete` | Create **one ACL per operation**; do **not** create a read ACL |
| **Name** | `cmdb_key_value` | Table picker → **Key Value**; leave the field box empty |
| **Decision type** | `Allow if` | Grants access when the role matches |
| **Active** | `true` | Inactive ACLs are ignored |
| **Admin overrides** | `false` | On an **existing** ACL, do **not** change this field |
| **Advanced** | `false` | Leave **Condition** and **Script** empty |
| **Application** | `Global` | |
| **Requires role** | `cmdb_inst_admin` | Related list → **Edit** → select role → **Save** |
| **Description** | *(optional)* | e.g. automation label sync for `admin_brooks_lab` |

To create or update these ACLs, go to **All → Access Control** and select **Access
Control (ACL)**. Filter **Name = `cmdb_key_value`**; optionally filter **Active =
true**. Look for **create**, **read**, **write**, and **delete** operations. If
**create**, **write**, or **delete** Allow-if ACLs do not exist, create an ACL for
**`cmdb_inst_admin`** per Table 6.3. If an ACL for the operation already exists,
ensure its fields match Table 6.3 — except do **not** change **Admin overrides** on an
existing ACL. Do **not** edit the active **read** ACL. Ignore inactive rows and
**`cmdb_key_value_v2`** (a different table).

Further context: [Tag_Based_Service_Mapping.md](Tag_Based_Service_Mapping.md).

#### 6.3.1 Elevate `security_admin` (prerequisite)

Table ACL edits require a human operator who can **elevate to `security_admin`**. On
shared demo instances (for example **optimizincdemo1**), two configuration steps are
often missing even after **`security_admin`** is assigned to a user:

1. The **`security_admin`** role must have **Elevated privilege = true** on the role
   record (otherwise **Profile → Elevate role** shows an empty **Available roles**
   list).
2. The operator user must be granted **`security_admin`** and must **log out and back
   in** after the grant.

Perform **Part A** once per instance. Perform **Part B** for each human operator who
will edit ACLs (for example **Gary Brooks** / `gbrooks` on optimizincdemo1).

**Part A — `security_admin` role (instance maintainer)**

Use an account that already has full admin access (typically **`admin`**) — not the
operator who will perform ACL edits unless they already hold **`admin`**.

1. Open **User Administration → Roles** (Filter navigator: `sys_user_role.list`).
2. Open the **`security_admin`** role.
3. Confirm **Elevated privilege** is checked (**true**).
   - If the field is read-only, an instance maintainer may need to adjust the field ACL
     on **`sys_user_role`** temporarily (common on hardened instances).
4. **Save** the role.
5. Optional API check (as a user who can read roles):
   ```bash
   # Expect elevated_privilege=true in the result
   curl -s -u "$SN_USER:$SN_PASSWORD" \
     'https://optimizincdemo1.service-now.com/api/now/table/sys_user_role?sysparm_query=name=security_admin&sysparm_fields=name,elevated_privilege' \
     | python3 -m json.tool
   ```
   On some instances the role record is hidden from non-admin REST callers; use the UI
   in that case.

**Part B — Operator user profile (who performs ACL changes)**

The operator needs **`security_admin`** assigned directly (group inheritance also
works). They do **not** need **`admin`** for the **`cmdb_key_value`** ACL task alone.

1. **User Administration → Users** → open the operator (for example **Gary Brooks** /
   **`gbrooks`**).
2. **Roles** related list → confirm **`security_admin`** is present.
   - Do not confuse with **`agent_security_admin`** or **`security_dashboard_user`**
     — those are different roles and do not replace **`security_admin`** for ACL
     edits.
3. If **`security_admin`** is missing, an instance admin adds it (**Edit** → select
   **`security_admin`** → **Save**). A user cannot grant themselves roles they do not
   already hold.
4. Operator **logs out completely** and signs back in (session cache refresh).
5. Operator opens **Profile** (avatar menu) → **Elevate role**.
6. Under **Available roles**, select **`security_admin`** → **Update**.
   - If the list is still empty, return to **Part A** (Elevated privilege not set) or
     repeat step 4 (stale session).
7. Perform §6.3 ACL edits while elevated.
8. When finished, **log out** (elevation ends with the session) or leave elevation
   only for the duration of the security task.

**Part C — Verify elevation before ACL edits**

| Check | Expected |
| ----- | -------- |
| **Profile → Elevate role** lists **`security_admin`** | Checkbox visible; **Update** enabled |
| After elevation, **System Security → Access Control** opens | ACL forms editable (not read-only) |
| Without elevation, same ACL form | Read-only or insufficient privilege |

Alternative when elevation cannot be configured: use the **`admin`** account (or another
user who already has active **`security_admin`** without needing elevation) to perform
§6.3 once.

#### OOB ACL state (typical demo instance)

From a typical OOB/demo instance:

| Operation | Active ACL? | Decision | Requires role | Action needed |
| --------- | ----------- | -------- | ------------- | ------------- |
| **read** | Yes | Allow if | **`cmdb_read`** | **No operator action** — read already works |
| **query_range** | Yes | Allow if | (varies) | **Leave unchanged** — list/range queries, not REST insert |
| **create** | No (inactive Deny unless) | — | — | **Create new** Allow if ACL |
| **write** | No (inactive Deny unless) | — | — | **Create new** Allow if ACL |
| **delete** | No (inactive Deny unless) | — | — | **Create new** Allow if ACL |

ServiceNow uses **write** for record updates (PATCH). There is no separate **modify**
operation on table ACLs.

**Do not:**

- Activate the existing inactive **Deny unless** **create** / **write** / **delete** rows.
- Edit **`cmdb_key_value_v2`** ACLs or the active **query_range** ACL.
- Edit the active **read** ACL.

#### Verify

1. End **`security_admin`** elevation (log out or de-elevate per instance policy).
2. Run discovery:

   ```bash
   cd ansible
   ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/start.yml \
     -e @../vars/secrets.yaml
   ```

3. In ServiceNow: **`cmdb_key_value.list`** → **Key** =
   `servicenow.com/service-instance` → expect rows on container CIs.

4. Optional Table API spot-check (expect **201**, not **403**):

   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' -u "$SN_USER:$SN_PASSWORD" \
     -H 'Content-Type: application/json' \
     -d '{"configuration_item":"<container_ci_sys_id>","key":"servicenow.com/service-instance","value":"Grafana"}' \
     'https://optimizincdemo1.service-now.com/api/now/table/cmdb_key_value'
   ```

#### After ACL change

Re-run CSDM diagnose if application services were waiting for tags:

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/diagnose.yml -e @../vars/secrets.yaml
```

### 6.4 Phase 3 install sequence

**Prerequisite:** complete [§6.3](#63-enable-automation-to-update-key-value-pairs) if using tag-based Service Mapping for Docker.

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/deploy.yml \
  -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/start.yml \
  -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/test.yml \
  -e @../vars/secrets.yaml
```

See `discovery/docker/README.md` for playbook details.

### 6.5 Tag-based Service Mapping — Observability Application Services

**When:** After **§6.3** (`cmdb_key_value` ACLs), **§6.4** (`discovery/docker/start.yml`), and **`csdm/deploy.yml`** for `observability-platform.csdm.yaml`.

**Who:** **`csdm/deploy.yml`** runs **`sn-sync-inject`** as the automation user (`admin_brooks_lab`). Tag Categories (Step A below) require **`service_mapping_admin`** on your interactive user ( **`sm_admin`** is often absent on Zurich).

**Why the CMDB map shows “add an entry point”:** CSDM creates service instance rows with **`service_mapping: tags`** and **`discover: false`**, reclassed to **`cmdb_ci_service_by_tags`**. The CMDB Service Map widget defaults to the **vertical** path until tag-based population runs. **`sn-sync-inject`** (via **`csdm/deploy.yml`**) applies the tag population rule from each spec’s display name (**`name:`**) via the Service Mapping Operations Scripted REST API (**`/populate_tags`**). **Do not add entry points** for observability Docker services.

#### What automation covers vs what stays manual

| Step | Automated | Playbook / action |
| ---- | --------- | ----------------- |
| Delete + recreate Service Instances | Yes | `sn-sync-delete --ci …` then `csdm/deploy.yml` / `sn-sync-inject` (see below) |
| BA → BS → service instance hierarchy + `depends_on` | Yes | `csdm/deploy.yml` → `sn-sync-inject` |
| Container CIs + `servicenow.com/*` tags | Yes (after §6.3) | `discovery/docker/start.yml` |
| Tag population rule per Service Instance (`tag_list`) | Yes | `sn-sync-inject` when `service_mapping: tags` |
| Tag Category (instance-wide) | Yes | `service-mapping/deploy.yml` (via scoped REST; included in `csdm/deploy.yml`) |
| Membership (`svc_ci_assoc`) workload → Service Instance | **ServiceNow** (after tags + rules exist) | `SNC.ServicePopulatorRunner('INTERACTIVE')`, triggered by inject |

For every service instance with **`service_mapping: tags`** in a `*.csdm.yaml` file, **`sn-sync-inject`** POSTs a **`tag_list`** to the Scripted REST **`/populate_tags`** operation (script under `ansible/playbooks/servicenow/service-mapping/files/sm_populate_tag_list.js`), which sets the population rule via **`SMServiceByTagsUtils.updateServiceFromTagsList()`**, sets service metadata, and triggers **`SNC.ServicePopulatorRunner('INTERACTIVE')`**.

Once tag filters exist, ServiceNow re-evaluates maps when new containers match — no per-container rule is needed.

#### Reset observability Application Services (test instance)

```bash
cd ansible
OBS="/home/gxbrooks/repos/spark-observability/specifications/servicenow/regions/brooks-lab"

# 1. Delete named service instances (BA/BS retained)
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/undeploy.yml \
  -e @../vars/secrets.yaml \
  -e "{\"sn_csdm_spec_paths_override\": [\"$OBS/observability-platform.csdm.yaml\"], \
       \"sn_csdm_delete_cis\": [\"Elasticsearch\", \"Kibana\", \"Grafana\", \"Prometheus\", \
       \"Grafana Tempo\", \"OpenTelemetry Collector\", \"Logstash\"]}"

# 2. Recreate from CSDM spec (skip horizontal discovery trigger for faster run)
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/deploy.yml \
  -e @../vars/secrets.yaml \
  -e "{\"sn_csdm_spec_paths_override\": [\"$OBS/observability-platform.csdm.yaml\"], \"sn_csdm_trigger_horizontal_discovery\": false}"

# 3. Sync container tags (requires §6.3 ACLs)
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/start.yml \
  -e @../vars/secrets.yaml
```

Override variable **`sn_csdm_spec_paths_override`** limits `csdm/deploy.yml` / `undeploy.yml` to one or more spec files.

#### Step A — Tag Categories (once per instance)

**Role:** **`service_mapping_admin`** (from plugin `com.snc.service-mapping`). Do **not** search for **`sm_admin`** — that role record is often missing on Zurich even when Service Mapping is installed.

**Install stack first:**

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/service-mapping/install.yml \
  -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/service-mapping/deploy.yml \
  -e @../vars/secrets.yaml
```

The tag category is created automatically by **`service-mapping/deploy.yml`** (also run at the start of **`csdm/deploy.yml`**) via **`service-mapping/tasks/ensure-tag-categories.yml`**; the tag key variable is **`sn_csdm_tag_key_service_instance`** in **`service-mapping/common/vars.yml`**.

**Manual fallback** (when deploy output shows tag category errors):

1. Sign in as a user with **`service_mapping_admin`**.
2. Filter Navigator → **CI tag categories** (table `svc_tag_categories`), or open  
   [classic Tag Categories list](https://optimizincdemo1.service-now.com/now/nav/ui/classic/params/target/svc_tag_categories_list.do).
3. An **empty list is normal** on a greenfield instance — click **New** and create:

| Tag Category (name) | Label key (`tag_key`) |
| ------------------- | --------------------- |
| **Service Instance** | `servicenow.com/service-instance` |

The Service Mapping Workspace URL (`/now/svc-map/tag-categories`) may be unavailable when the **`sn_itom_map_app`** Store package cannot be downloaded on a shared demo; classic **CI tag categories** is sufficient for brooks-lab. See [ServiceNow tag mapping doc](https://www.servicenow.com/docs/r/it-operations-management/service-mapping/map-service-tag.html) (role: **`service_mapping_admin`**).

#### Step B — Tag population (automated by `sn-sync-inject` / `csdm/deploy.yml`)

When **`service_mapping: tags`** is set on a service instance in a `*.csdm.yaml` file, **`sn-sync-inject`** configures tag-based population automatically after the CI is created or updated. The tag is derived from the spec:

| CSDM field | Tag key |
| ---------- | ------- |
| **`name`** (display name; sanitized to the K8s label charset when `platform: kubernetes`) | `servicenow.com/service-instance` |

For observability-platform, values match `observability/docker-compose.yml` labels:

| Service Instance | `servicenow.com/service-instance` |
| ------------------- | ------------------------------------------------ |
| Elasticsearch | `Elasticsearch` |
| Kibana | `Kibana` |
| Grafana | `Grafana` |
| Prometheus | `Prometheus` |
| Grafana Tempo | `Grafana Tempo` |
| OpenTelemetry Collector | `OpenTelemetry Collector` |
| Logstash | `Logstash` |

Deploy output shows **`Tag SM <name>: HTTP 202`** for each service when population succeeds. **`service_status`** may remain **requirements** until workload tags exist and the Service Populator runs.

**Verify tags before blaming SM:** `cmdb_key_value.list` filtered on key `servicenow.com/service-instance`. If rows are missing, complete [§6.3](#63-enable-automation-to-update-key-value-pairs) and re-run `discovery/docker/start.yml`.

**Verify membership:** `svc_ci_assoc.list` with service = Service Instance sys_id — tag-based SM adds matching CIs as **members** in `svc_ci_assoc` (no `cmdb_rel_ci` **Contains** edges are created). The deploy triggers `SNC.ServicePopulatorRunner('INTERACTIVE')` so membership recalculates immediately.

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/csdm/diagnose.yml -e @../vars/secrets.yaml
```

#### Manual fallback (UI or CLI)

Use these when troubleshooting outside **`sn-sync-inject`**:

- **Service Mapping Workspace** → per-service **Tags** filter (same keys/values as the table above).
- **ServiceNow CLI** (`snc service-graph app-service populate` with `population_method.type: tag_list`) — see [Automating Application Service Registration](https://www.servicenow.com/community/cmdb-articles/automating-application-service-registration-with-best-practices/ta-p/3275122).
- **CSDM UI flow:** [Populate application services using tags](https://www.servicenow.com/docs/r/it-operations-management/service-mapping/map-service-tag.html).

Further context: [Tag_Based_Service_Mapping.md](Tag_Based_Service_Mapping.md), [DT_Problems_to_SN_Event.md](../../specifications/dynatrace/docs/DT_Problems_to_SN_Event.md#observability-application-services--tag-based-map-bootstrap-brooks-lab), [csdm/README.md](../../ansible/playbooks/servicenow/csdm/README.md).

---

## 7. Phase 4 — Dynatrace SGC and Event Management

Phase 4 adds **Service Graph Connector for Observability – Dynatrace** (topology import) and
**Event Management** push (problems → `em_event`). Detailed mapping and event-field reference:
`tmp/Dynatrace-ServiceNow SGC.md`, `tmp/Dynatrace-ServiceNow-events.md`.

Playbooks: `ansible/playbooks/servicenow/sgc/` (Dynatrace-specific configuration
under `sgc/sources/dynatrace/`, events under `sgc/sources/dynatrace/events/`).

### Automation posture

Store app and plugin installation **is automated** by `sgc/install.yml`
(manifest, CI/CD App Repo Install by scope in manifest order, plugin
activation, progress polling, re-verification). Implementation details live in
the playbook, not in this document.

What remains manual is a one-time **bootstrap** that the automation user
cannot perform for itself:


| One-time prerequisite                                 | Why it cannot be automated                                                                |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Grant `admin_brooks_lab` the roles in the table below | A user cannot grant itself roles; requires an instance admin (Optimiz on the shared demo) |
| Plugin `**com.snc.ci_cd`** active                     | Provides the `sn_cicd` REST endpoints — the CI/CD API cannot activate itself              |
| Store entitlement / first-time license click-through  | Contractual acceptance is UI-only in ServiceNow Store                                     |


On an instance we own, the first two could also be scripted under an admin
credential; on optimizincdemo1 they are requests to the instance owners.
Without the bootstrap, `sgc/install.yml` degrades to a state report plus the
manual steps below.

### Bootstrap sequence (interleaved manual / automated steps)

**Ordering constraint:** a role record only exists once the app that delivers
it is installed. `sn_cicd.sys_ci_automation` ships with the CI/CD tooling, so
on a bare instance the **plugin activation must precede the role grant**. On
**optimizincdemo1 the CI/CD tooling is already present** (CICD Spoke v2.0.2;
`/api/sn_cicd` endpoints answer 400/403, not 404), so the role **can be
granted up front** and the sequence collapses to steps 3–4.

`sgc/install.yml` runs a bootstrap preflight
(`sgc/tasks/check-cicd-bootstrap.yml`) whenever components need installing:
it checks that the role record exists and that the automation user holds it,
and **fails fast naming the exact missing manual step**. The interleaving is
therefore just *run → perform the reported step → re-run* — the playbook is
idempotent and skips completed work.


| #   | Actor                                                                                    | Step                                                                                                                                                                                                                 |
| --- | ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | instance admin (manual, once)                                                            | Create automation user, grant Phase 1–3 roles (§1–2); extend `**cmdb_key_value`** ACLs for `**cmdb_inst_admin**` ([§6.3](#63-enable-automation-to-update-key-value-pairs)) when using tag-based Docker/CSDM |
| 2   | instance admin (manual, once, **only if** the preflight reports the role record missing) | Activate plugin `com.snc.ci_cd` (System Definition → Plugins) — the CI/CD API cannot activate its own plugin                                                                                                         |
| 3   | instance admin (manual, once)                                                            | Grant `sn_cicd.sys_ci_automation`, `sn_appclient.app_client_user`, `evt_mgmt_admin`, and `connection_admin` (see the roles table) to `admin_brooks_lab`                                                              |
| 4   | automation                                                                               | Run `sgc/install.yml` — installs everything else; re-run after any grant                                                                                                                                             |
| 5   | operator (manual, once)                                                                  | Guided Setup (section E below)                                                                                                                                                                                       |


### Roles required by the automation user (`admin_brooks_lab`)


| Role                           | Needed for (tables / APIs)                                                                                                                                                                                                                                                          |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cmdb_inst_admin`              | CMDB tables — `cmdb_ci_*`, `cmdb_rel_ci`, `sys_object_source`; Identification/Reconciliation API `/api/now/identifyreconcile`. **Also requires** [§6.3 table ACL extension](#63-enable-automation-to-update-key-value-pairs) on `**cmdb_key_value`** for Docker label sync |
| `discovery_admin`              | Discovery configuration and status — `discovery_schedule`, `discovery_status`, `ecc_agent` (MID server), `ecc_queue`                                                                                                                                                                |
| `evt_mgmt_admin`               | Event Management — `em_event`, `em_alert`, event rules                                                                                                                                                                                                                              |
| `rest_service`                 | Inbound REST web-service access (basic-auth API calls as this user)                                                                                                                                                                                                                 |
| `sn_appclient.app_client_user` | `sys_store_app` read (App Manager visibility) — latest-version / update-available reporting in `diagnose.yml`. Not needed to install: the App Repo Install API takes the scope directly                                                                                             |
| `connection_admin`             | Connections & Credentials — `http_connection` (SGC connection Hostname set by `sgc/sources/dynatrace/deploy.yml`); `api_key_credentials` is writable without it                                                                                                                     |
| `sn_cicd.sys_ci_automation`    | CI/CD API — `/api/sn_cicd/app_repo/install` (by scope), `/api/sn_cicd/plugin/{id}/activate`, `/api/sn_cicd/progress/{id}` (plugin entitlement checks for CMDB 360 and SGC install)                                                                                                  |
| `snc_platform_rest_api_access` | Platform REST APIs — Table API `/api/now/table/*` (incl. `sys_scope`, `sys_user_role`, `sys_user_has_role`)                                                                                                                                                                         |


### Required Store applications and plugins (install order)

The authoritative manifest — names, scopes, install order, and **pinned
versions** — is `**specifications/servicenow/integrations/sgc/store_apps.yml`** (`sn_store_apps`; sgc-local
because only the sgc playbooks consume it). `sgc/install.yml` consumes it;
`sgc/diagnose.yml` reports installed vs pinned vs latest versions. Update pins
there after a deliberate upgrade.

Install in this order. Later apps depend on earlier ones.


| #   | Name                                                  | Scope / ID                             | Type      | Purpose                                                   |
| --- | ----------------------------------------------------- | -------------------------------------- | --------- | --------------------------------------------------------- |
| 1   | Observability Commons for CMDB                        | `sn_observability`                     | Store app | Required before SGC; notification payload template step   |
| 2   | Integrations Commons for CMDB                         | `sn_cmdb_int_util`                     | Store app | IH/RTE/IRE commons for SGC                                |
| 3   | CMDB CI Class Model                                   | `sn_cmdb_ci_class`                     | Store app | CSDM class model for SGC mappers                          |
| 4   | ITOM Discovery License                                | `com.snc.itom.discovery.license`       | Plugin    | Discovery entitlement (usually already on ITOM instances) |
| 5   | Event Management                                      | `sn_em_ai`                             | Store app | `em_event` processing, push connector listener            |
| 6   | IntegrationHub Data Stream action type                | `com.glide.hub.action_type.datastream` | Plugin    | Required for SGC scheduled imports                        |
| 7   | Service Graph Connector for Observability – Dynatrace | `sn_dynatrace_integ`                   | Store app | SGC + Dynatrace push connector (`source=SGO-Dynatrace`)   |


`sgc/install.yml` attempts plugin activation via the CI/CD API; on strict or
shared instances plugins may still need a manual **Request Plugin** (step B
below) or a ServiceNow HI case.

### Manual Store install — step-by-step (fallback)

Run `sgc/install.yml` first — it skips installed components and tells you what
remains. Use these manual steps when the automated path is blocked (missing
`sn_cicd.sys_ci_automation`, no Store entitlement, first-time license
click-through, or plugin requests requiring an HI case).

Assumes Zurich UI; navigation names may vary slightly by role.

#### A. Resolve entitlement and roles

Use an account with `**admin`** or `**sn_appclient.app_client_company_installer**`
(and Store access) — first-time UI installation requires the company-installer
role; `sn_appclient.app_client_user` alone does not grant it. For post-install
Ansible, also grant `admin_brooks_lab`:


| Additional role                  | Why                                                                                                                                                                          |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **evt_mgmt_admin**               | Read/create `em_event`; validate event integration                                                                                                                           |
| **sn_cicd.sys_ci_automation**    | App Repo Install + plugin activation API                                                                                                                                     |
| **sn_appclient.app_client_user** | Least-privilege read on `sys_store_app` (latest-version reporting); the installer role is **not** needed for the automated path — install authority comes from the CI/CD API |
| **cmdb_inst_admin**              | Already on automation user for Phases 1–3                                                                                                                                    |


Coordinate with **Optimiz / instance owners** before installing on a shared demo.

#### B. Request the Data Stream plugin (once per instance)

1. Navigate to **System Applications → All Available Applications → Request Plugin** (or **System Definition → Plugins**).
2. Search `**com.glide.hub.action_type.datastream`**.
3. Click **Request Plugin** / **Activate** and wait until state is **Active** (may require ServiceNow HI case on strict instances).

#### C. Install each Store application (repeat for the Store apps in the table above)

1. Open **System Applications → All Available Applications** (or **ServiceNow Store** from the app navigator filter).
2. Search for the exact application name (e.g. `Service Graph Connector for Observability - Dynatrace`).
3. Open the application record → **Install** (or **Get** then **Install** from Store).
4. Choose **Install** (not **Install with Demo Data** unless you explicitly want demo content).
5. Wait for install to complete (progress in **System Applications → Installation History** or the overlay).
6. Confirm **Application State = Installed** and scope appears under **System Applications → Application Menus** (e.g. filter `Dynatrace Observability`).

**Tips:**

- Install **one app at a time** on busy shared instances to avoid “another update operation is active”.
- If Install is disabled, check **Company → Subscriptions**, dependency apps (previous row in table), or ask instance admin for Store entitlement.
- The automated path does not need package `sys_id`s — the CI/CD App Repo Install API takes the application scope directly.

#### D. Verify installs (Table API or UI)

```text
sys_scope.scope = sn_dynatrace_integ          → row exists
sys_store_app.scope IN (sn_observability, sn_dynatrace_integ, sn_em_ai, …) → active
```

Or run:

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/diagnose.yml -e @../vars/secrets.yaml
```

Expected after success: `scoped app (sn_dynatrace_integ): INSTALLED` and a
per-component version report (installed vs pinned vs latest).

#### Application maintain modes (`install.yml`)

Use when the scoped app is installed but instance metadata is corrupt (for
example Import Log `NullPointerException` on transform with orphaned RTE
field mappings):


| Mode              | Variable                    | API                                                         | When to use                                        |
| ----------------- | --------------------------- | ----------------------------------------------------------- | -------------------------------------------------- |
| Install (default) | `sn_sgc_app_mode=install`   | CI/CD App Repo Install                                      | Missing Store apps/plugins                         |
| Repair            | `sn_sgc_app_mode=repair`    | App Manager `GET .../app/repair?appId=&version=`            | Re-apply app files without uninstall               |
| Reinstall         | `sn_sgc_app_mode=reinstall` | App Manager `GET .../app/install?...&isReinstall=true`      | Full reinstall of same version                     |
| Reset (lab)       | `sn_sgc_app_mode=reset`     | REST DELETE orphaned RTE mappings + optional SGO CMDB purge | Fix Import NPE without admin UI; data rediscovered |


```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/install.yml \
  -e @../vars/secrets.yaml -e sn_sgc_app_mode=repair

# Lab instance — purge corrupt RTE metadata (no admin password required)
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/install.yml \
  -e @../vars/secrets.yaml -e sn_sgc_app_mode=reset
```

Target scope(s): `sn_sgc_maintain_scopes` (default `[sn_dynatrace_integ]`).

**Full uninstall + reinstall:** ServiceNow exposes **no CI/CD uninstall API**.
Uninstall (with **Retain tables and data** unchecked) requires **admin** or
`**sn_appclient.app_client_company_installer`** in the UI. The automation user
can install missing apps but cannot uninstall an installed version — CI/CD
`reinstall=true` fails with *Application version is currently installed*, and
App Manager repair/reinstall fails preprocessing with `id: null`.

**Reset mode (automated alternative):** When lab data may be discarded,
`reset` deletes orphaned `sys_rte_eb_field_mapping` rows across all
SGO-Dynatrace RTE feeds (the NPE root cause). The scoped app stays installed;
run `sources/dynatrace/deploy.yml` and `sources/dynatrace/start.yml` afterward.

**Limits:** Repair/reinstall use the App Manager API, not
`/api/sn_cicd/app_repo/install` (which rejects an already-installed version).
The automation user may queue the job but fail preprocessing with
`Unable to process schema and dependencies for id: null` — in that case use
**System Applications → Applications → Service Graph Connector for
Observability - Dynatrace → Repair** with a full **admin** account (steps 1–3
below), then continue with steps 4–5.

**Version compatibility:** `diagnose.yml` and `install.yml` call
`tasks/validate-compatibility.yml`, which checks:

- ServiceNow platform family (from `glide.war`) against Store compatibilities
- Installed dependency versions against `sn_dynatrace_integ` Store-declared
dependencies (currently `sn_cmdb_int_util:2.25.0`, `sn_cmdb_ci_class:1.83.0`
for v1.15.0)
- Orphaned RTE field mappings on **SGO-Dynatrace Hosts** (transform NPE root cause)

Pins in `specifications/servicenow/integrations/sgc/store_apps.yml` match the Store dependency matrix for
v1.15.0.

**After repair — run import (steps 4–5):**

1. `playbooks/servicenow/sgc/sources/dynatrace/start.yml` — queues Execute Now
  and monitors the cascade (or run Execute Now manually; see deploy.md).
2. Confirm Import Log has no `NullPointerException`; lab feeds reach `processed`.

#### E. Source deploy (mostly automated)

The connection, credential, management-zone scoping, and import-schedule
activation are automated by
`playbooks/servicenow/sgc/sources/dynatrace/deploy.yml`. **No Guided Setup
card requires manual configuration** — all six (app v1.14.x) are covered:


| Guided Setup card                    | Manual action needed                                                                        |
| ------------------------------------ | ------------------------------------------------------------------------------------------- |
| Enable Access To SNC.ImpactManager   | None — automated by `deploy.yml`                                                            |
| Basic (credential, connection, test) | None — automated by `deploy.yml`; optional *Test Connection* sanity check                   |
| Configure Dynatrace Grail OAuth      | None — optional feature, not used; Skip                                                     |
| Advanced                             | None — **do not run** *Configure Problem Notification* (owned by `events/deploy.yml`); Skip |
| Add Multiple Instances               | None — single-instance setup; Skip                                                          |
| Set up scheduled import jobs         | None — schedule activated by `deploy.yml`                                                   |


See `../sgc/sources/dynatrace/docs/deploy.md` for the detailed card map,
Dynatrace token model, and manual fallbacks. Remaining manual steps **outside**
the wizard:

1. Grant `connection_admin` to `admin_brooks_lab` (one-time; lets the playbook
  set the connection Hostname).
2. Optional: run Basic card **Test Connection** as a sanity check.

Import execution is automated by `sources/dynatrace/start.yml` after
`deploy.yml`. Then verify `**sys_object_source*`* rows with `name=SGO-Dynatrace` and CMDB
CIs with `discovery_source=SGO-Dynatrace` (`sgc/diagnose.yml`).

#### F. Ansible after SGC is installed

```bash
cd ansible
# Re-run event deploy — switches webhook to source=SGO-Dynatrace when scope detected
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/diagnose.yml -e @../vars/secrets.yaml
```

### Phase 4 install sequence (summary)

```bash
# 0. One-time manual bootstrap (see "Bootstrap sequence" above): activate
#    com.snc.ci_cd only if the preflight reports it missing; grant
#    sn_cicd.sys_ci_automation; Store entitlement / license click-through if
#    prompted. install.yml fail-fasts naming the missing step — re-run after.

# 1. Store apps + plugins (idempotent; skips installed components)
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/install.yml -e @../vars/secrets.yaml

# 2. Manual: Guided Setup (section E above) — connection, filters,
#    scheduled imports, notification payload template

# 3. Verify component versions / SGC / CMDB merge state
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/diagnose.yml -e @../vars/secrets.yaml

# 4. Fail-fast if SGC still missing (or proceed after install)
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/deploy.yml -e @../vars/secrets.yaml

# 5. Dynatrace alerting + webhook (brooks-lab objects only)
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/deploy.yml -e @../vars/secrets.yaml

# 6. Generate load + validate events
cd ../spark/apps/data-analysis-book && ./bin/run-chapters.sh -a
ansible-playbook -i inventory.yml playbooks/servicenow/sgc/sources/dynatrace/events/test.yml -e @../vars/secrets.yaml
```

### Not automatable (manual, one-time or per-upgrade)


| Action                                                                                                          | Where                                            | Why not automated                                                                                                             |
| --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| Grant roles (`sn_cicd.sys_ci_automation`, `sn_appclient.app_client_user`, `evt_mgmt_admin`, `connection_admin`) | User Administration                              | Role grants require instance admin on the shared demo                                                                         |
| Configure **`security_admin`** elevation + operator profile | User Administration → Roles / Users | See [§6.3.1](#631-elevate-security_admin-prerequisite); required before ACL edits |
| Create **`cmdb_key_value`** Allow-if ACLs for **`cmdb_inst_admin`** (create, write, delete) | System Security → Access Control | Table ACL change requires elevated **`security_admin`**; read usually needs no change — see [§6.3](#63-enable-automation-to-update-key-value-pairs) |
| Store entitlement / license click-through                                                                       | ServiceNow Store / Subscriptions                 | Contractual acceptance is UI-only                                                                                             |
| Plugin request when CI/CD activation is denied                                                                  | System Definition → Plugins / HI case            | Strict instances gate plugin activation                                                                                       |
| Scheduled Data Imports first execution                                                                          | Dynatrace Observability → Scheduled Data Imports | Operator-triggered; monitor Concurrent Import Sets                                                                            |


**Required IDs / prerequisite configuration:**


| Variable                                           | Where                                               | Purpose                                                                          |
| -------------------------------------------------- | --------------------------------------------------- | -------------------------------------------------------------------------------- |
| `SN_INSTANCES` (`url`, `short_name`, …)            | `vars/variables.yaml` (service-now)                 | Instance identity per target; `SN_URL` is Demo1's URL (the non-Ansible tools derive the active instance instead) |
| `DT_API_URL`, `DT_AUTOMATION_TOKEN`, `DT_MANAGEMENT_ZONE` | `vars/variables.yaml` (dynatrace-ansible) / secrets | Dynatrace side                                                                   |
| `sn_store_apps`                                    | `specifications/servicenow/integrations/sgc/store_apps.yml` (sgc-local)             | App/plugin manifest: scopes, install order, pinned versions                      |


Package `sys_id`s are **not** configuration and are not needed — `install.yml`
installs by application **scope** via the CI/CD App Repo Install API.

### Do not override others’ work (shared demo)

**Naming convention for brooks-lab automation:**


| System     | Prefix / name pattern                            | Examples                                             |
| ---------- | ------------------------------------------------ | ---------------------------------------------------- |
| Dynatrace  | `Spark Observability`, `Spark Lab`, `brooks-lab` | Alerting profile, metric event, problem notification |
| ServiceNow | `brooks-lab` location scope                      | CMDB rows, Discovery schedules                       |


**Ansible idempotency rules:**

- Dynatrace objects are upserted by **displayName/summary** (`Spark Observability - ServiceNow brooks-lab`, etc.) — does **not** modify `Default`, `DemoProfile - Optimiz`, or `**ServiceNow Demo 1 - Optimiz`**.
- Problem notification deploy **copies payload template** from pre-existing `ServiceNow Demo 1 - Optimiz` only when creating the brooks-lab notification; it does **not** update Demo 1.
- ServiceNow Discovery/K8/Docker playbooks scope to `**brooks-lab`** location and named schedules — they do not delete or reconfigure unrelated CMDB CIs.

**Pre-existing tenant configuration (not created by this repo):**


| Object                                                              | Status                                                                                             |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Dynatrace problem notification `**ServiceNow Demo 1 - Optimiz`**    | **Pre-existing** — webhook to `optimizincdemo1…/inbound_event?source=dynatrace&sys_id=712a39811…`  |
| ServiceNow EM push connector `**712a39811ba483105488a937b04bcba5`** | **Pre-existing** — referenced by Demo 1 notification; **not** created or modified by our playbooks |
| Dynatrace notification `**ServiceNow optimiz demo3`**               | **Pre-existing** — **disabled**; now points at an httpdump.app URL, not Demo3 (checked 2026-11-23) |
| Dynatrace notification `**Legacy Demo 3`**                          | **Pre-existing** — enabled; `Otel Demo` alerting profile → Demo3 EM push connector `4d2f61174728db503a869b83616d4386` (`source=dynatrace`, no auth header) |


Contact **Optimiz / prior integrators** before changing Demo 1, connector `712a39811…`, or shared Dynatrace notifications.

**Created by brooks-lab automation (2026-06-08):**

- Dynatrace: `Spark Observability - ServiceNow brooks-lab` (alerting profile)
- Dynatrace: `Spark Lab - Host CPU above 80%` (metric event)
- Dynatrace: `ServiceNow brooks-lab - Spark Observability` (problem notification — used the legacy URL until SGC was installed; the legacy fallback was removed 2026-11-24, it now posts only to `source=SGO-Dynatrace`)

---

## Multiple ServiceNow instances

brooks-lab can feed **optimizincdemo1** or **optimizincdemo3**, one at a time. The
instance it currently feeds is the **active instance**. Design and status:
[Multi_Target_ServiceNow.md](Multi_Target_ServiceNow.md).

ServiceNow accounts are **per instance**. Each instance needs its own
`admin_brooks_lab` and `mid_brooks_lab` records with the roles in §1–§2. The
same User IDs are used everywhere, with a different password on each instance.

### Instance registry and the `target` flag

`vars/variables.yaml` → `SN_INSTANCES` lists every instance (keyed by `id`) with:
- its URL and short name, and its `secrets_suffix`;
- its MID Server name (`mid_server_name`) and installer `.deb` (`mid_installer_deb_url`);
- its Dynatrace problem-notification name (`dt_problem_notification_name`);
- the SGC Dynatrace API token name (`dt_sgc_api_token_name`).

Every ServiceNow playbook takes `-e target=<id>`; `target=all` is rejected. Nothing
records which instance is active: every run **derives** it from the Lab3 MID
(`config.xml` `url` and service running), the enabled brooks-lab Dynatrace problem
notification, and the KVA informer Helm release (`instance.name`, replicas). An
instance is active only when all three agree; `servicenow/diagnose.yml` is the
consistency check and fails at its end otherwise. Without `-e target`, switch and any modes use the active
instance, else the MID's owner (e.g. after `stop.yml`); active mode requires a
consistent active instance. See
[Multi_Target_ServiceNow.md](Multi_Target_ServiceNow.md#the-active-instance-is-derived-never-recorded).

```bash
# Which instance owns the MID, the KVA informer and the Dynatrace notifications
ansible-playbook -i inventory.yml playbooks/servicenow/diagnose.yml
# Switch the lab to Demo1 (start the MID, run the SGC import)
ansible-playbook -i inventory.yml playbooks/servicenow/start.yml -e target=demo1
# Read-only check of an instance, active or not
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/diagnose.yml -e target=demo3
# Stop feeding the active instance (stop the MID, park the KVA informer, disable its notification)
ansible-playbook -i inventory.yml playbooks/servicenow/stop.yml
```

How it works:

- Each ServiceNow playbook imports `playbooks/servicenow/tasks/target.yml` as its
  first play, with a mode set by its verb:
  - `switch` (every `install.yml`, `deploy.yml`, `start.yml`): point the lab at the
    target first. Disable the other instances' brooks-lab Dynatrace problem
    notifications; if another instance owns the Lab3 MID, reconfigure it for the
    target (it then auto-upgrades to the target's build); repoint the KVA informer
    via Helm, or park it when the target lacks the Kubernetes Visibility Agent app;
    make sure the MID's signing key is active and the MID validated; enable the
    target's notification. Nothing changes when everything already points at the
    target.
  - `active` (every `discover.yml` and `test.yml`, `discovery/host/deploy.yml`,
    `discovery/k8s/start.yml`): require a consistent active instance
    (fail listing the inconsistencies otherwise); fail when `-e target` names
    another instance.
  - `any` (every `diagnose.yml`, `csdm/undeploy.yml`, `stop.yml`,
    `discovery/stop.yml`): either instance; inconsistencies are reported as an
    ignored ERROR and the playbook continues, with a note when the target is not
    active. `servicenow/diagnose.yml` then fails at its end when no instance is
    fully active.
- Resolution and activation happen once per run. Guards in nested imports and
  aggregators (including the whole-lab `playbooks/deploy.yml`) reuse the result.
- Every service-management playbook runs the guard; the OneAgent pod labelling
  in `discovery/k8s/start.yml` and `events/deploy.yml --tags openpipeline`
  touch only Kubernetes pods and the Dynatrace tenant.

Each `servicenow/*/common/vars.yml` derives these from the selected entry:
`sn_url`, `sn_user`, `sn_password`, `sn_mid_*`, `sn_instance_short_name`,
`dt_sn_problem_notification_name` and `dt_sgc_api_token_name`.

Deploy facts are written per instance, for **every** instance including Demo1:
`vars/contexts/servicenow_discovery_deploy_<id>.json`,
`servicenow_k8s_discovery_deploy_<id>.json` and `servicenow_sm_deploy_<id>.json`.

The non-Ansible readers (`servicenow/comparator`, `create-sn-change-window.py`) can't
reach the MID or the cluster, so `servicenow/sn_active_instance.py` derives the active
instance from the Dynatrace signal alone: the instance whose brooks-lab notification is
the only one enabled. `SN_TARGET=<id>` overrides it; they fail when no instance, or more
than one, is enabled.

**Incident rules follow the active instance.** `incident/deploy.yml` changes
Event Management for the whole instance:
- EM properties;
- Automated grouping;
- the OOTB "Create Incident for Primary Alert" rule;
- the `EvtMgmtCustomIncidentPopulator` Script Include;
- the maintenance rules.

It runs on whichever instance is active, Demo3 included (the Demo3 hold was lifted
2026-11-24). These settings stay on an instance after a switch away.

### Secrets naming

The unsuffixed keys belong to Demo1 (`secrets_suffix: ""`). Every other instance uses the
same keys with its `secrets_suffix` (`_DEMO3`):

```yaml
servicenow:
  # optimizincdemo1 (demo1)
  SN_USER: "admin_brooks_lab"
  SN_PASSWORD: "<plaintext password>"
  SN_MID_USER: "mid_brooks_lab"
  SN_MID_PASSWORD: "<plaintext password>"
  SN_DT_WEBHOOK_USER: ...        # written by sgc/sources/dynatrace/events/deploy.yml
  SN_DT_WEBHOOK_PASSWORD: ...

  # optimizincdemo3 (demo3)
  SN_USER_DEMO3: "admin_brooks_lab"
  SN_PASSWORD_DEMO3: "<plaintext password>"
  SN_MID_USER_DEMO3: "mid_brooks_lab"
  SN_MID_PASSWORD_DEMO3: "<plaintext password>"
  SN_DT_WEBHOOK_USER_DEMO3: ...  # written by events/deploy.yml -e target=demo3
  SN_DT_WEBHOOK_PASSWORD_DEMO3: ...
```

Passwords must be **plaintext**, because REST Basic Auth and the MID agent send
them as typed. Values shaped like `$s$<salt>$<hash>` are ServiceNow's stored
hash from `sys_user.user_password` and cannot be used to sign in.

### One MID Server on Lab3, owned by the active instance

A MID Server registers with exactly one instance (`url` in its `config.xml`), and the
vendor `.deb` is one `agent` package with one install path. Lab3 therefore runs **one**
MID: systemd unit `mid_brooks_lab3`, directory `/opt/servicenow/mid/agent`. Its
`ecc_agent` name follows the owner:

| Instance | MID name (`mid_server_name`) |
| -------- | ---------------------------- |
| demo1 | `mid-brooks-lab3` |
| demo3 | `mid-brooks-lab3-demo3` |

A switch-mode playbook with a target that does not own the MID
(`tasks/activate-mid-server.yml`):

- **reconfigures** it (`discovery/tasks/reconfigure-mid-server.yml`): stops the
  service, backs up `config.xml`, sets the target's `url`, `mid.instance.username`,
  `mid.instance.password` and `name` (`mid_server_name`), drops `mid_sys_id`, and
  starts the service. The MID finds its `ecc_agent` record on the target by name and
  **auto-upgrades to the target's build** (Zurich ↔ Australia);
- installs the target's `.deb` (cached in `/var/cache/servicenow-mid/`) only when
  Lab3 has no MID, or uninstalls and reinstalls it with
  `-e sn_mid_switch_method=reinstall`;
- waits for the target's `ecc_agent` record to come Up (up to 20 minutes, covering
  the auto-upgrade);
- makes sure the MID's signing key is active (`tasks/ensure-mid-signing-key.yml`).
  Both Demo1 and Demo3 use MID signing keys (`ecc_agent_signing_key`). When the
  owner changed or the key isn't active it re-keys: invalidate, restart, wait for a
  new key, validate, restart, wait for it to become `active`. Without this the MID
  fails to register (HTTP 400) because the instance holds a key the MID's keystore
  lacks. See [Multi_Target_ServiceNow.md](Multi_Target_ServiceNow.md#mid-signing-keys);
- validates it.

The old instance's `ecc_agent` record stays, and shows Down.

**MID service control (polkit).** Auto-upgrade restarts the MID with `bin/mid.sh`,
which calls `systemctl start|stop|restart` as the MID user without sudo. A polkit
rule, `/etc/polkit-1/rules.d/50-servicenow-mid.rules`
(`discovery/tasks/ensure-mid-service-control.yml`), lets that user start, stop and
restart `mid_brooks_lab3.service`; without it the upgrade fails and leaves the MID
stopped. The former `/etc/sudoers.d/servicenow-mid` was ineffective (sudo is never
called) and is removed.

The `.deb` is used only for a fresh install or `sn_mid_switch_method=reinstall`, and
must match each instance's build. Set `mid_installer_deb_url` per instance from that
instance's **MID Server → Downloads**.

On 2026-11-23 a second MID (`mid-brooks-lab3-demo3`) was unpacked from the `.deb`
into `/opt/servicenow/mid-demo3/agent` so both instances ran at once. That layout is
retired: when the owning instance's MID is already installed, a switch removes any
extra MID trees and units.

### Dynatrace problem notifications per instance

`sgc/sources/dynatrace/events/deploy.yml -e target=<id>` upserts one Dynatrace
problem notification **per instance**, named by `dt_problem_notification_name`. All of
them use the same `Spark Observability - ServiceNow brooks-lab` alerting profile, and
**only the active instance's notification is enabled**; a switch disables the others
and enables the target's. Other teams' notifications are never modified. The URL is
the OOTB SGO-Dynatrace push connector (`source=SGO-Dynatrace`); `events/deploy.yml`
requires SGC on the target (the legacy-connector fallback was removed 2026-11-24).

### Creating the users on an instance

As an instance admin, in that instance's UI:

1. **All → System Security → Users → New**.
2. **User ID** `admin_brooks_lab` (or `mid_brooks_lab`), **Identity type** Machine,
   **Web service access only** ticked. Save.
3. **Set Password**, and store the same plaintext in the instance's
   `SN_PASSWORD_<INSTANCE>` / `SN_MID_PASSWORD_<INSTANCE>`.
4. **Roles** related list: the §1 roles for `admin_brooks_lab`, and only
   `mid_server` for `mid_brooks_lab`.

Check the instance first. Shared demo instances may already have a
`mid_brooks_lab`; don't reset another person's password (see
[Do not override others' work](#do-not-override-others-work-shared-demo)).

---

## Installation sequence

Run from the `automation/ansible/` directory. These commands target the active instance
(the default); add `-e target=<id>` to switch the lab to another instance:

```bash
# 0. Permission and connectivity check
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/diagnose.yml \
  -e @../vars/secrets.yaml

# 1. sn-discovery on Lab1–Lab3; MID Server package on Lab3
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/install.yml \
  -e @../vars/secrets.yaml

# 2. ServiceNow objects (location, credential, range, schedule)
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/deploy.yml \
  -e @../vars/secrets.yaml

# 3. Validate MID Server "Up" in ServiceNow UI:
#    MID Server > Servers > mid-brooks-lab3-demo3 (Demo3) or mid-brooks-lab3 (Demo1)

# 4. On-demand Discovery scan
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/start.yml --tags discovery_scan \
  -e @../vars/secrets.yaml

# 5. Assert Linux server CIs (after scan completes)
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/test.yml \
  -e @../vars/secrets.yaml
```

Install only the discovery SSH account (skip MID):

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/install.yml \
  -e @../vars/secrets.yaml --tags discovery_user
```

---

## Troubleshooting


| Symptom                              | Check                                                                                                             |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| `deploy.yml` 403 on Discovery tables | `admin_brooks_lab` roles; run `diagnose.yml`                                                                      |
| `cmdb_key_value` REST insert 403     | Complete [§6.3](#63-enable-automation-to-update-key-value-pairs); re-run `discovery/docker/start.yml` |
| MID stays Down                       | `mid_brooks_lab` has `mid_server`; password matches `/opt/servicenow/mid/agent/config.xml`; `&` in password XML-escaped |
| 401 against a non-default instance   | Using that instance's `*_<INSTANCE>` secrets? Is the value plaintext, not a `$s$…$…` hash? |
| MID user cannot run deploy           | Expected — use `admin_brooks_lab` (`SN_USER`)                                                                     |
| No CIs after scan                    | MID Up; schedule linked to range + credential; wait for scan completion                                           |
| Duplicate CIs                        | Hostnames must be `Lab1.lan`, `Lab2.lan`, `Lab3.lan` consistently                                                 |


---

## Related documentation

- [DT_SN_Specification_Guide.md](DT_SN_Specification_Guide.md) — **primary modeling guide** for CSDM, runtime labels, and Dynatrace alignment
- [Tag_Based_Service_Mapping.md](Tag_Based_Service_Mapping.md) — tag-based Service Mapping UI and `cmdb_key_value`
- [CSDM_Specifications.md](CSDM_Specifications.md) — CSDM YAML schema and deploy processor rules
- [DT_SN_Comparison_Process.md](DT_SN_Comparison_Process.md) — compare workflow (`servicenow/comparator/`)
- [../../ansible/playbooks/servicenow/README.md](../../ansible/playbooks/servicenow/README.md) — Ansible playbook layout
- [../../ansible/playbooks/servicenow/discovery/README.md](../../ansible/playbooks/servicenow/discovery/README.md) — discovery playbook verbs
- [../../ansible/playbooks/servicenow/discovery/docker/README.md](../../ansible/playbooks/servicenow/discovery/docker/README.md) — Docker container sync and label upsert
- [../../ansible/playbooks/servicenow/discovery/k8s/start.yml](../../ansible/playbooks/servicenow/discovery/k8s/start.yml) — Kubernetes pod label sync
- [../../ansible/playbooks/servicenow/discovery/host/deploy.yml](../../ansible/playbooks/servicenow/discovery/host/deploy.yml) — host agent tags on linux_server CIs
- [../../docs/architecture-and-resources.md](../../docs/architecture-and-resources.md) — Lab3 MID memory budget
- `tmp/ServiceNow_Dynatrace_Integration.md` — CMDB / Dynatrace design
- `tmp/Dynatrace-ServiceNow SGC.md` — SGC / IRE mapping
- `tmp/Dynatrace-ServiceNow-events.md` — event paths, field mapping, webhook comparison

