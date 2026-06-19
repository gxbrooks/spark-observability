# ServiceNow Discovery (Phase 1)

Automates brooks-lab Discovery:

1. **install.yml** — `sn-discovery` SSH account on all K8s nodes (Lab1–Lab3);
   MID Server package + systemd on Lab3 (`observability` host).
2. **deploy.yml** — ServiceNow location `brooks-lab`, SSH credential, subnet
   range `192.168.1.0/24`, CI Discovery schedule bound to MID `mid-brooks-lab3`.
3. **discover.yml** — Preflight lab hosts, then trigger a schedule run via the
   **Discovery Operations API** deployed by `deploy.yml`.
4. **diagnose.yml** — API permissions, MID state, credential presence.
5. **test.yml** — Assert lab Linux server CIs exist in CMDB after a scan.
6. **stop.yml** / **start.yml** — MID Server service lifecycle on Lab3.

## brooks-lab identification

Per ServiceNow best practice, the **Discovery schedule** sets `location` to a
`cmn_location` record named `brooks-lab`. Discovered CIs inherit that location.
The schedule name is `Brooks Lab CI Discovery`.

## Discovery scope vs credentials

- **IP range:** entire lab subnet `192.168.1.0/24` (horizontal discovery).
- **SSH credentials:** only Lab1.lan, Lab2.lan, Lab3.lan — other addresses may
  appear as network or unknown devices without login.

## Variables (service-now context)

Non-secret settings are in `vars/variables.yaml` with `contexts: [service-now]`.
Playbooks load `vars/contexts/servicenow_ansible_vars.yml` (auto-regenerated).

## MID Server install

- Native install under `SN_MID_INSTALL_DIR` (default `/opt/servicenow/mid-brooks-lab3`).
- Requires `SN_MID_USER` / `SN_MID_PASSWORD` with `mid_server` role.
- `SN_MID_INSTALLER_DEB_URL` in `variables.yaml` (service-now context) — build-specific
  Linux `.deb`; see `../docs/install.md`.
- Ubuntu workaround: ServiceNow’s `.deb` declares `Depends: glibc` (RHEL name). `install.yml`
  builds `files/glibc-control` with `dpkg-deb` before installing the agent package so apt is not
  left broken (blocks unrelated packages such as LibreOffice).

## Playbook pattern

Follows `standards/automation.md`: install → deploy → discover (operator) →
diagnose / test.
