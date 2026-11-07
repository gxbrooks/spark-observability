# OneAgent

Host-level Dynatrace OneAgent (Classic Full Stack: installer script run
directly on the OS), split out from `dynatrace/` for the same reason
`elastic-agent/` is its own top-level module rather than living under
`observability/elasticsearch/`: it's a host agent, not SaaS/tenant
configuration, and has its own install/uninstall lifecycle independent
of the Dynatrace backend config in `automation/terraform/dynatrace_settings.tf`.

## Two OneAgent deployment modes exist in this project

| Mode | Managed by | Scope |
|---|---|---|
| **Cloud Native Full Stack** (DaemonSet) | `specifications/dynatrace/dynakube/dynakube.yaml.j2` applied via Terraform (`kubectl_manifest`) + the Dynatrace Operator | Kubernetes nodes (`kubernetes_master`, `kubernetes_workers`) -- the currently-active path in this lab |
| **Classic Full Stack** (host install) | This module (`install.yml`/`uninstall.yml`) | Any host, including non-Kubernetes ones |

**Do not run both on the same node.** Dynatrace documents this as an
anti-pattern -- duplicate host-unit consumption and conflicting agent
injection. As of 2026-11, the host installer has never actually been
run against any lab host (binary absent, service inactive on
Lab1/Lab2/Lab3) -- Cloud Native Full Stack is the only active OneAgent
path here. This module's main value today is for a host that is *not*
a Kubernetes node, or if the project ever moves away from Cloud Native
Full Stack.

## Verbs

- `install.yml` / `uninstall.yml` -- host OneAgent installer/uninstaller script.
- `start.yml` / `stop.yml` -- informational only (report expected-inactive status on Kubernetes nodes; there's no host service for these to actually start/stop there).
- `diagnose.yml` -- reports both deployment modes: the DaemonSet's status (from `kubernetes_master`) and the host service's status (on every targeted host), since only one is expected to be doing anything per node.

No `check.yml`: OneAgent isn't deployed from a declarative representation file the way Elasticsearch/Kibana's config is, so there's no spec-vs-deployed drift to compare (per `standards/automation.md`, a module may omit a verb the way the service is built makes unnecessary).

## Related

- `automation/ansible/playbooks/observability/dynatrace/` -- the Dynatrace SaaS backend config and Operator/webhook/ActiveGate lifecycle. Imports this module's playbooks are wired at `automation/ansible/playbooks/observability/{install,start,stop,diagnose,uninstall}.yml`, alongside the `dynatrace/*.yml` imports, both gated by `observability_dynatrace_enabled`.
- `automation/terraform/dynatrace_k8s.tf` / `dynatrace_lifecycle.tf` -- the Dynakube CR and Operator/webhook scaling Terraform manages.
