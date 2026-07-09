# Cursor session state — 2026-07-09 (lab shutdown)

Saved before **~1 week** lab hiatus. Resume here when bringing the environment back.

## What was completed this session

### NFS / application logs (node-local)

- **`/mnt/spark/logs`** removed from NFS exports; **local bind** from `/var/local/spark/logs` on all K8s nodes (`ansible/playbooks/nfs/install.yml`).
- **`dtuser`** added to supplementary group **`spark`** for OneAgent log tailing.
- Client log path: **`/mnt/spark/logs/spark-client/<hostname>/`** (`run-chapters.sh`).
- Documentation: `spark/docs/nfs-mounts.md`, `docs/File_System_Architecture.md`.

### Dynatrace / OpenPipeline

- Client `event.name`: `Application log {level} on spark-client-{instance}` (hostname from path).
- **`resolve-k8s-pod-entity`** remains disabled (HOST problems; SN pod rebind).

### Validation run (2026-07-09 ~06:45 CDT)

1. Restarted **DynaKube OneAgent** daemonset + host watchdog on Lab1–Lab3.
2. Lab3 OneAgent: `FILE_STATUS_OK` for `/mnt/spark/logs/spark-client/*/spark-app.log`.
3. Full chapter load (03–10) on Lab3: **127 WARN**, **7 ERROR** in client log.
4. **Alert0014495** — bundled client + master WARN; **Lab3-only** `dt.source_entity`; alert CI = **spark-master-0** (see `Davis_Bundling_Issue.md`).

### Documentation added

- `servicenow/docs/Problem_to_Incident/Davis_Bundling_Issue.md` — worked example Alert0014495.

## Open work when you return

1. **Davis bundling remediation** — `K8sLogPodCiBind` vs client path priority; incident CI to Spark Client AS on bundled alerts.
2. **Re-run client-only validation** after `playbooks/start.yml` with ≥15m gap from master-heavy work.
3. **Optional:** `nfs/install.yml` idempotent busy-umount on Lab2 if not fully applied.
4. **`run-parallel-all.sh`** — replace `rg` with `grep` on Lab3 if used.

## Environment shutdown (this session)

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/stop.yml
```

Then hosts powered off in order: **Lab1 → Lab2 → Lab3**.

## Bring-back checklist

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/start.yml
# After K8s up:
ansible-playbook -i inventory.yml playbooks/spark/start.yml -e '{"restart": true}'
# Verify local logs bind on all nodes:
ansible kubernetes_master:kubernetes_workers -i inventory.yml -m shell -a 'findmnt /mnt/spark/logs' -b
# Restart OneAgent if log paths were stale:
ansible Lab3 -i inventory.yml -m shell -a 'sudo -u gxbrooks kubectl rollout restart daemonset/dynakube-oneagent -n dynatrace' -b
```

## Key ServiceNow artifacts (last successful client detection)

| Item | ID |
|------|-----|
| SGO alert (bundled) | Alert0014495 |
| Legacy child | Alert0014496 |
| Incident (host CI) | INC0013902 |
| Dynatrace problem | P-2607343 |
| Lab3 HOST entity | HOST-D8207A117616460E |

## Git

All session changes committed and pushed to `origin/main` before shutdown (see commit message on 2026-07-09).
