# ServiceNow Discovery — installation guide (Phase 1)

This document covers **prerequisites** on the ServiceNow instance and lab hosts,
then the Ansible install sequence for brooks-lab Discovery.

**Instance:** https://optimizincdemo1.service-now.com/  
**Playbooks:** `ansible/playbooks/servicenow/discovery/`  
**Variables:** `vars/variables.yaml` → **`service-now`** context → generated
`vars/contexts/servicenow_ansible_vars.yml`  
**Secrets:** `vars/secrets.yaml` → `servicenow:` block (see `vars/secrets.example.yaml`)

---

## Prerequisites overview

Phase 1 needs **three separate identities**. They must not be combined into one
ServiceNow user.

| Identity | Where it lives | Purpose |
| -------- | -------------- | ------- |
| **admin_brooks_lab** | ServiceNow (`SN_USER`) | Ansible REST automation — locations, credentials, schedules |
| **mid_brooks_lab** | ServiceNow (`SN_MID_USER`) | MID Server agent authentication only |
| **sn-discovery** | Linux on Lab1–Lab3 | SSH target for Discovery classification probes |

---

## 1. ServiceNow user: `admin_brooks_lab`

Used by Ansible `deploy.yml`, `discover.yml`, `diagnose.yml`, and `test.yml`.
Mapped to `servicenow.SN_USER` in `vars/secrets.yaml`.

### User record

| Field | Value |
| ----- | ----- |
| **User ID** | `admin_brooks_lab` |
| **Identity type** | Machine |
| **Web service access** | Enabled (required for REST Table API / Basic Auth) |
| **Interactive login** | Not required |

### Required roles (minimum effective set)

Grant enough rights to **read and write** Discovery configuration tables and
CMDB locations. On optimizincdemo1 the following roles are effective:

| Role | Why |
| ---- | --- |
| **discovery_admin** | Discovery schedules, ranges, credentials, run scans *(or equivalent ACLs via elevated CMDB/admin roles)* |
| **cmdb_inst_admin** | Create/update `cmn_location` (**brooks-lab**) |
| **rest_service** | REST API access |
| **snc_platform_rest_api_access** | Table API authentication |
| **cmdb_query_builder** or **cmdb_read** | `test.yml` CMDB validation |

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

| Field | Value |
| ----- | ----- |
| **User ID** | `mid_brooks_lab` |
| **Identity type** | Machine |
| **Web service access** | Enabled |
| **Interactive login** | Not required |

### Required roles

| Role | Required |
| ---- | -------- |
| **mid_server** | **Yes — only role needed** |

Do **not** grant `discovery_admin`, `admin`, or `itil` to this user unless
ServiceNow support documents a specific exception. Least privilege is
`mid_server` alone.

### Password and `config.xml`

The User ID and password must match `mid.instance.username` and
`mid.instance.password` in the MID `config.xml` on Lab3 (rendered by
`discovery/install.yml`).

If the password contains **`&`**, `<`, `>`, or quotes, the install template
XML-escapes it automatically. Prefer passwords without `&` when rotating, to
avoid encoding mistakes in manual edits.

### What the MID user cannot do (verified)

`mid_brooks_lab` with **`mid_server` only** is **not sufficient to complete
Phase 1 by itself**:

| Action | MID user | admin_brooks_lab |
| ------ | -------- | ---------------- |
| Authenticate MID agent / ECC queue | Yes | N/A |
| Read `ecc_agent` (MID registration) | Yes | Yes |
| Create `cmn_location` (brooks-lab) | **No** | Yes |
| Create `discovery_credentials` | **No** | Yes |
| Create `discovery_schedule` / ranges | **No** | Yes |
| Run `deploy.yml` / `discover.yml` | **No** | Yes |

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

| Field | Value |
| ----- | ----- |
| **Username** | `sn-discovery` (override: `SN_DISCOVERY_USER` in `variables.yaml`) |
| **Auth** | SSH public key (generated on controller) |
| **Sudo** | Limited NOPASSWD for Discovery classification commands |
| **Purpose** | Target credential for SSH-based Linux CI Discovery on lab servers |

Private key path (gitignored): `vars/sn_discovery_id_ed25519`  
Uploaded to ServiceNow as credential **`brooks-lab-ssh`** by `deploy.yml`.

---

## 4. Instance and lab prerequisites

### ServiceNow instance

- [ ] ITOM **Discovery** and **CMDB** licensed/active on the instance
- [ ] `admin_brooks_lab` and `mid_brooks_lab` created with roles above
- [ ] `SN_URL` set in `vars/variables.yaml` (service-now context; not a secret)
- [ ] `vars/secrets.yaml` populated (both users, passwords)
- [ ] Copy `vars/secrets.example.yaml` field names if migrating from older `lab_admin` naming

### Lab hosts

- [ ] Lab1, Lab2, Lab3 powered on and reachable via Ansible inventory
- [ ] Lab3 outbound HTTPS (443) to `optimizincdemo1.service-now.com`
- [ ] Lab3 can reach `192.168.1.0/24` for Discovery scans
- [ ] ~4–6 GiB RAM headroom on Lab3 for MID JVM (see `docs/architecture-and-resources.md`)

### MID Server package

- [ ] `SN_MID_INSTALLER_DEB_URL` in `vars/variables.yaml` (service-now context)
  points at the Linux `.deb` that matches the **instance build**.

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
4. Update `SN_MID_INSTALLER_DEB_URL` in `variables.yaml` and re-run
   `discovery/install.yml --tags mid_server`.

The MID installer build **must** match the instance; a mismatch prevents the MID
from registering or causes ECC queue failures.

### brooks-lab Discovery scope (configured by `deploy.yml`)

| Object | Name / value |
| ------ | ------------- |
| Location | `brooks-lab` (`cmn_location`) |
| IP range | `192.168.1.0/24` |
| SSH credential | `brooks-lab-ssh` → `sn-discovery` |
| Schedule | `Brooks Lab CI Discovery` |
| MID Server name | `mid-brooks-lab3` (Lab3) |

Only Lab1–Lab3 have SSH credentials; other addresses on the subnet may appear
as network or unclassified devices.

---

## 5. Kubernetes prerequisites (Phase 2 — KVA Informer)

Phase 2 discovers the brooks-lab Kubernetes cluster into CMDB via the **Kubernetes
Visibility Agent (KVA) Informer** only. Cluster identity is shared with Dynatrace
so CMDB and observability stay aligned on one **K8-native cluster name**.

### Variable model (`vars/variables.yaml`)

All Kubernetes cluster definitions live in the **Kubernetes** section of
`variables.yaml`. Use **K8-prefixed** names (not `SN_` or `DT_`) for constructs
that exist in the cluster itself.

| Variable | Purpose |
| -------- | ------- |
| **`K8S_PRIMARY_CLUSTER`** | Name of the cluster this repo manages (`brooks-lab`). Used by KVA Helm (`clusterName`), Dynatrace DynaKube annotation, auto-tags, and management zones. |
| **`K8S_CLUSTERS`** | Multi-entry registry (list). Each entry describes one cluster known to the shared ServiceNow instance. |
| **`K8S_KVA_HELM_REPO`** | ServiceNow KVA Informer Helm repository URL. |

Regenerate context files after editing:

```bash
cd vars && ./generate_contexts.sh service-now
# or: ansible-playbook ... discovery/common/regenerate_context.yml
```

Generated outputs: `vars/contexts/servicenow_ansible_vars.yml` (includes
`K8S_CLUSTERS` and `K8S_PRIMARY_CLUSTER`).

### `K8S_CLUSTERS` entry fields

Each list item in `K8S_CLUSTERS` supports:

| Field | Required | Description |
| ----- | -------- | ----------- |
| **`name`** | Yes | Kubernetes cluster name in CMDB and Dynatrace (must match KVA `clusterName`). |
| **`location`** | Yes | `cmn_location.name` in ServiceNow (`k8s/deploy.yml` creates location if missing). |
| **`location_full_name`** | Recommended | Display name for `cmn_location` when created by deploy. |
| **`primary`** | Yes | Exactly one entry should be `true` — the cluster this repo actively manages. |
| **`managed`** | Yes | `true` = run `k8s/install.yml` (KVA on cluster). `false` = CMDB location only. |
| **`kva_namespace`** | When managed | Namespace for KVA Informer (e.g. `servicenow-kva`). |
| **`api_url`** | Optional | Kubernetes API URL (documentation / future use). |
| **`environment`** | Optional | `on-prem`, `azure`, etc. |
| **`cloud_provider`** | Optional | Cloud provider when applicable. |

**Example (current optimizincdemo1):**

```yaml
K8S_PRIMARY_CLUSTER:
  value: brooks-lab
  contexts: [ansible, devops, service-now]

K8S_CLUSTERS:
  value:
    - name: brooks-lab
      location: brooks-lab
      location_full_name: Brooks Lab
      primary: true
      managed: true
      api_url: https://192.168.1.207:6443
      kva_namespace: servicenow-kva
      environment: on-prem
    - name: aks-otel-demo
      location: bradens-cloud
      location_full_name: Braden Cloud Demo
      primary: false
      managed: false
      environment: azure
      cloud_provider: azure
  contexts: [ansible, service-now]
```

No ServiceNow custom mapping table is required. `K8S_CLUSTERS` is the GitOps
source; `k8s/deploy.yml` applies locations to cluster CIs and installs the
instance business rule that inherits `cluster.location` to child K8s CIs.

### Dynatrace alignment

`K8S_PRIMARY_CLUSTER` replaces the former `DT_K8S_CLUSTER_NAME`. After changing
the cluster name, redeploy Dynatrace so DynaKube, auto-tags, and management zones
match:

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/observability/dynatrace/deploy.yml \
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

## 6. Docker prerequisites (Phase 3 — Lab3 observability stack)

Phase 3 registers running Docker containers from the Lab3 observability Compose
stack into CMDB. Location is inherited from the **Linux server CI** (`lab3`) via
an instance business rule — the same GitOps pattern as Kubernetes.

### Variable model (`vars/variables.yaml`)

Docker host definitions live in **`vars/variables.yaml`** (immediately after
`K8S_CLUSTERS`). Use **Docker-prefixed** names (not `SN_`) for host/stack constructs.

| Variable | Purpose |
| -------- | ------- |
| **`DOCKER_PRIMARY_HOST`** | Name of the primary managed Docker stack (`lab3-observability`). |
| **`DOCKER_HOSTS`** | Multi-entry registry (list). Each entry describes one Docker host/stack. |

Regenerate context files after editing:

```bash
cd vars && ./generate_contexts.sh -f service-now
```

### `DOCKER_HOSTS` entry fields

| Field | Required | Description |
| ----- | -------- | ----------- |
| **`name`** | Yes | Logical stack name (used in playbooks and logs). |
| **`location`** | Yes | Expected `cmn_location.name` (inherited from host CI via business rule). |
| **`location_full_name`** | Recommended | Display name when location is created by deploy. |
| **`primary`** | Yes | Exactly one entry should be `true`. |
| **`managed`** | Yes | `true` = run `docker/discover.yml` sync for this host. |
| **`cmdb_host_name`** | Yes | CMDB Linux server name (e.g. `lab3` from Phase 1). |
| **`ansible_host`** | When managed | Inventory host to run `docker ps` on (e.g. `Lab3`). |
| **`compose_dir`** | Optional | Compose project directory name (documentation). |
| **`description`** | Optional | Human-readable stack description. |

**Example (current optimizincdemo1):**

```yaml
DOCKER_PRIMARY_HOST:
  value: lab3-observability
  contexts: [ansible, service-now]

DOCKER_HOSTS:
  value:
    - name: lab3-observability
      location: brooks-lab
      location_full_name: Brooks Lab
      primary: true
      managed: true
      cmdb_host_name: lab3
      ansible_host: Lab3
      compose_dir: observability
      description: Lab3 observability Docker Compose stack
  contexts: [ansible, service-now]
```

Phase 1 must have discovered **`lab3`** with `location=brooks-lab` before Phase 3.
`docker/deploy.yml` installs business rule **`docker-inherit-location-from-host`**
so new/updated `cmdb_ci_docker_container` rows copy `host.location`.

### Phase 3 install sequence

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/deploy.yml \
  -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/discover.yml \
  -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/test.yml \
  -e @../vars/secrets.yaml
```

See `discovery/docker/README.md` for playbook details.

---

## Installation sequence

Run from the `ansible/` directory:

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
#    MID Server > Servers > mid-brooks-lab3

# 4. On-demand Discovery scan
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/discover.yml \
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

| Symptom | Check |
| ------- | ----- |
| `deploy.yml` 403 on Discovery tables | `admin_brooks_lab` roles; run `diagnose.yml` |
| MID stays Down | `mid_brooks_lab` has `mid_server`; password matches `config.xml`; `&` in password XML-escaped |
| MID user cannot run deploy | Expected — use `admin_brooks_lab` (`SN_USER`) |
| No CIs after scan | MID Up; schedule linked to range + credential; wait for scan completion |
| Duplicate CIs | Hostnames must be `Lab1.lan`, `Lab2.lan`, `Lab3.lan` consistently |

---

## Related documentation

- `../README.md` — playbook layout
- `../discovery/README.md` — playbook verbs
- `docs/architecture-and-resources.md` — Lab3 MID memory budget
- `tmp/ServiceNow_Dynatrace_Integration.md` — CMDB / Dynatrace design
