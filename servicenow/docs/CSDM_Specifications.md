# CSDM Specifications — moved

The CSDM specification TPG and stylesheet now live in the **sn-sync** project:

- [`~/repos/sn-sync/docs/CSDM_Specifications.md`](../../../sn-sync/docs/CSDM_Specifications.md)
- [`~/repos/sn-sync/docs/csdm-spec.css`](../../../sn-sync/docs/csdm-spec.css)

Ansible playbooks under `ansible/playbooks/servicenow/csdm/` remain in this repository until the Python utility fully replaces them. Prefer the Python operators `sn-sync-inject` / `sn-sync-delete` for new work (see `~/repos/sn-sync/docs/usage.md`).
