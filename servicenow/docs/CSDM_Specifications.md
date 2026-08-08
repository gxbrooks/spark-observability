# CSDM Specifications — moved

The CSDM specification TPG and stylesheet now live in the **csdm-injector** project:

- [`~/repos/csdm-injector/docs/CSDM_Specifications.md`](../../../csdm-injector/docs/CSDM_Specifications.md)
- [`~/repos/csdm-injector/docs/csdm-spec.css`](../../../csdm-injector/docs/csdm-spec.css)

Ansible playbooks under `ansible/playbooks/servicenow/csdm/` remain in this repository until the Python utility fully replaces them. Prefer the Python operators `csdm-inject` / `csdm-delete` for new work (see `~/repos/csdm-injector/docs/usage.md`).
