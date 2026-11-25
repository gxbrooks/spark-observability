# ServiceNow Discovery (Phase 1)

Automates brooks-lab Discovery:

1. **install.yml** — `sn-discovery` SSH account on all K8s nodes (Lab1–Lab3);
   MID Server package + systemd on Lab3 (`observability` host).
2. **deploy.yml** — ServiceNow location `brooks-lab`, SSH credential, subnet
   range `192.168.1.0/24`, CI Discovery schedule bound to the target
   instance's MID (`mid-brooks-lab3` on Demo1, `mid-brooks-lab3-demo3` on Demo3).
   Writes `vars/contexts/servicenow_discovery_deploy_<id>.json`.
3. **discover.yml** — Preflight lab hosts, then trigger a schedule run via the
   **Discovery Operations API** deployed by `deploy.yml`.
4. **diagnose.yml** — API permissions, MID state, credential presence.
5. **test.yml** — Assert lab Linux server CIs exist in CMDB after a scan.
6. **stop.yml** / **start.yml** — MID Server service lifecycle on Lab3.
   `stop.yml` stops the MID only when it belongs to the target instance;
   `start.yml` switches the lab to the target first.

Every playbook takes `-e target=demo1|demo3` (default: the active instance); see
[../README.md](../README.md#target-instance--e-target).

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

- One MID on Lab3, owned by the active instance: the vendor package in
  `/opt/servicenow/mid/agent`, systemd unit `mid_brooks_lab3`. Its `ecc_agent`
  name is `SN_INSTANCES.<id>.mid_server_name` (`mid-brooks-lab3` for Demo1,
  `mid-brooks-lab3-demo3` for Demo3).
- Switching instances (any install/deploy/start with another target)
  **reconfigures** the MID (`tasks/reconfigure-mid-server.yml`: `config.xml`
  url, user, password, name; `mid_sys_id` dropped); the MID then auto-upgrades
  to the target's build. The target's `.deb` (cached in
  `/var/cache/servicenow-mid/`) is installed only when Lab3 has no MID or with
  `-e sn_mid_switch_method=reinstall` (uninstall via
  `tasks/uninstall-mid-server.yml`, then install). See
  [Multi_Target_ServiceNow.md](../../../../../specifications/servicenow/docs/Multi_Target_ServiceNow.md).
- Auto-upgrade restarts the unit with `systemctl` (no sudo), so
  `tasks/ensure-mid-service-control.yml` installs a polkit rule
  (`/etc/polkit-1/rules.d/50-servicenow-mid.rules`) letting the MID user
  start/stop/restart `mid_brooks_lab3.service`; the old, ineffective
  `/etc/sudoers.d/servicenow-mid` is removed.
- `tasks/ensure-mid-signing-key.yml` re-keys the MID (invalidate →
  restart → validate → restart) when its owner changed or its signing key is not
  active (both instances use MID signing keys).
- Requires `SN_MID_USER<suffix>` / `SN_MID_PASSWORD<suffix>` with the
  `mid_server` role on that instance.
- `SN_INSTANCES.<id>.mid_installer_deb_url` — build-specific Linux `.deb`
  (Demo1 Zurich, Demo3 Australia); see [specifications/servicenow/docs/install.md](../../../../../specifications/servicenow/docs/install.md).
- Ubuntu workaround: ServiceNow’s `.deb` declares `Depends: glibc` (RHEL name). `install.yml`
  builds `specifications/servicenow/integrations/discovery/glibc-control` with `dpkg-deb` before installing the agent package so apt is not
  left broken (blocks unrelated packages such as LibreOffice).

## Playbook pattern

Follows `standards/automation.md`: install → deploy → discover (operator) →
diagnose / test.
