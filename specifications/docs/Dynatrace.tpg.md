# Dynatrace and Dynatrace Monitors

This TPG governs how this environment's Dynatrace tenant is organized and how **monitors** — built-in
anomaly detectors, metric events, log events, and OpenPipeline Davis event processors — are authored,
so that Problems bind to entities that mean something downstream, repeated conditions correlate instead
of duplicating, and tenant configuration is reproducible rather than a product of UI muscle memory.

## Purpose

This TPG gives Dynatrace configuration authors, monitor authors, and the operators who triage the
Problems monitors produce one shared set of expectations, so that:

* A Problem's primary entity is one a downstream system (CMDB, ServiceNow, a dashboard) can act on,
  not an entity so short-lived it is gone by the time anyone looks at it.
* Two engineers authoring unrelated monitors reach for the same conventions — event identifiers,
  timeouts, merging behavior — without having to rediscover them from an existing processor each time.
* Tenant configuration lives in Ansible and/or Terraform as the system of record, so it can be
  reviewed, diffed, and reapplied, rather than depending on one person's memory of which Settings page
  a given object lives under.

It does not cover OneAgent/ActiveGate deployment topology, Kubernetes Operator lifecycle, or
log-to-incident correlation design on the ServiceNow side — see
[Observability — Service Management Documentation](../servicenow/docs/Log_to_Incident/Observability%20-%20Service%20Management%20Documentation.tpg.md)
for those.

## Definitions

**Tenant** — One Dynatrace environment (for example `pdt20158`), identified by its own API/UI host.

**Management zone (MZ)** — A named, rule-based scope over entities (by host group, Kubernetes cluster
name, workload name pattern, and similar), used to restrict what an alerting profile, a dashboard, or a
permission applies to.

**Host group** — A label assigned to OneAgent at install/configuration time, used both as a Settings
scope of its own and as a condition in management-zone rules.

**Entity** — Anything Dynatrace's topology model (Smartscape) tracks as a monitored object: a `HOST`, a
`PROCESS_GROUP`, a `PROCESS_GROUP_INSTANCE`, a `CLOUD_APPLICATION` (a Kubernetes workload), a
`KUBERNETES_POD`, a `SERVICE`, and similar.

**Stable entity** — An entity whose identity persists across the normal lifecycle of what it represents
— a `HOST`, a `PROCESS_GROUP`, or a `CLOUD_APPLICATION` (workload) — and so remains a meaningful thing
to alert on, report on, or bind a downstream CI to.

**Ephemeral entity** — An entity that is replaced far more often than the condition a monitor is meant
to describe — a `PROCESS_GROUP_INSTANCE`, a Pod, or a container — such that naming it as a Problem's
primary entity tells a reader almost nothing by the time they read it.

**Problem** — A Davis-correlated record representing one ongoing issue, with a primary ("affected")
entity, a severity, a start and (if closed) end time, and the Events that make up its evidence.

**Event** — One input to Davis's correlation: a metric threshold breach, a custom alert, a log-based
alert, or similar, each tied to a source entity.

**Monitor** — Any configured rule capable of producing a Problem or an Event: a built-in Davis anomaly
detector, a metric event, a classic log event, or an OpenPipeline Davis event processor. This TPG uses
"monitor" as the umbrella term across all four.

**OpenPipeline** — Dynatrace's configurable ingest-and-process framework for logs, events, and other
record types, organized into named pipelines, each with Processing and Davis stages.

**Davis processor** — A rule inside an OpenPipeline pipeline's Davis stage: a matcher expression plus a
set of event properties, that turns matching records into Events/Problems.

**Source entity** (`dt.source_entity`) — The Davis event property naming which entity the resulting
Event/Problem should attach to.

**Entity remapping** — Davis's own automatic correlation step, which, unless disabled per processor via
`dt.davis.is_entity_remapping_allowed: false`, may rebind an event to an entity Davis judges more
relevant than the one a processor explicitly named.

**Alerting profile** — A named filter (management zone plus severity levels, optionally tags) that
selects which Problems are eligible to be forwarded by a given problem notification.

**Problem notification** — An outbound integration (webhook or otherwise) that forwards Problems
selected by its alerting profile to an external system.

**Settings 2.0 object** — The generic `{schemaId, scope, value}` representation Dynatrace's Settings API
uses for nearly all tenant configuration — management zones, alerting profiles, problem notifications,
and OpenPipeline pipelines among them.

## Roles and Responsibilities

The **Dynatrace Tenant Administrator** owns tenant-wide settings not specific to any one monitor: API
tokens, OneAgent/ActiveGate/Operator deployment, host groups, and management zones. They grant the
access other roles need.

The **Monitor Author** designs and implements individual monitors — anomaly detectors, metric events,
log events, and OpenPipeline Davis processors. They are responsible for correct entity binding, event
naming, and merging/timeout behavior for every monitor they author.

The **Dynatrace IaC Maintainer** owns the Ansible and/or Terraform representation of tenant
configuration, keeps it the system of record, and resolves drift surfaced by a plan or dry run before
anyone else's apply has to absorb it.

The **Integration Owner** owns an outbound integration end to end: the problem notification/webhook
configuration on the Dynatrace side, and the downstream system's own expectations of the payload (for
example, a ServiceNow SGC field mapping).

The **Dynatrace Operator** triages Problems day to day, tunes alerting-profile thresholds and scope, and
reports a misbehaving monitor (wrong entity, duplicate Problems, noisy firing) back to its Monitor
Author rather than silently working around it downstream.

## Statements

### 1. Tenant Organization

1.1. Management zone rules **must** be defined by host group, Kubernetes cluster name, or a workload
   name pattern, not by naming individual entities one at a time, so new entities matching the pattern
   are automatically in scope.

1.2. A management zone rule scoping a `HOST` **should** enable propagation to the process groups running
   on it, so one host-level rule covers its dependent entities instead of requiring a separate rule per
   entity type.

1.3. A host group **must** be set at OneAgent/agent configuration time, not approximated afterward by
   management-zone rule alone, since host-group-scoped settings (including per-host-group overrides)
   depend on the agent-reported value.

### 2. Entity Binding

2.1. A monitor **must not** bind a Problem or Event to an ephemeral entity as its source entity when a
   corresponding stable entity can be determined.

2.2. Monitor authors **should** compute the intended source entity once, in the pipeline's Processing
   stage, as a single field — for example `coalesce(dt.entity.process_group, dt.entity.host)` for a
   host-based workload, or `coalesce(dt.entity.cloud_application, dt.entity.process_group, dt.entity.host)`
   for a Kubernetes one — rather than repeating the same fallback logic separately in every Davis
   processor that needs it.

2.3. Every Davis processor that sets `dt.source_entity` **must** also set
   `dt.davis.is_entity_remapping_allowed` to `false`. Without it, entity remapping is free to override
   the declared source entity — observed in practice to rebind a Problem back to the ephemeral entity
   the processor was specifically written to avoid.

2.4. Monitor authors **should** verify entity binding against a real Problem's `affectedEntities` (via
   the Problems v2 API or the Problem detail page), not only against the processor's own configuration —
   an entity-remapping failure is visible only in the resulting Problem, never in the static settings.

2.5. Downstream CMDB/CSDM modeling **must not** be relied on as the primary mechanism for correcting an
   ephemeral entity binding. Resolving an ephemeral CI to its stable CI after the fact is a safety net
   for Problems Dynatrace itself did not bind correctly, not a substitute for binding them correctly at
   the source.

### 3. Monitor Design

3.1. Every custom Davis event **must** set a stable, deterministic `event.unique_identifier` built from
   fields that identify the condition itself (environment, service instance, log signature, and
   similar), not from fields that vary per occurrence (a timestamp, a line number), so repeated
   occurrences of the same condition correlate into one Problem instead of creating duplicates.

3.2. Every custom Davis event **should** set `dt.davis.is_merging_allowed` to `false` unless the monitor
   is specifically intended to merge into unrelated Problems already open on the same entity.

3.3. Every custom Davis event **must** set an explicit `dt.davis.timeout` (minutes) rather than rely on
   Dynatrace's 15-minute default, so a Problem lives as long as the signal warrants. The OpenPipeline
   Davis processor reads `dt.davis.timeout`; a property named `dt.davis.event_timeout` is stored on
   the event but ignored (check the effective `dt.davis.timeout` on `fetch dt.davis.events`).

3.4. A log- or metric-based monitor that depends on upstream enrichment (for example, a
   `service_instance` tag or a pod-name field set earlier in the pipeline) **should** be paired with a
   second, fail-visible monitor that fires when that enrichment is absent, so a silent enrichment
   failure is itself a visible Problem rather than only producing a mis-bound or mis-labeled one.

3.5. A monitor's name and `event.name` template **must** include enough of the matched condition — log
   class and line, metric name, pod or workload name — that an operator can tell one firing monitor from
   another of the same type without opening the Problem's detail view.

3.6. Monitor authors **must not** reuse an existing Davis processor's `id` for an unrelated condition;
   processor `id`s are referenced from documentation, event filters, and dashboards outside the
   processor's own definition.

### 4. Alerting and Notification

4.1. An alerting profile **must** scope the Problems it selects by management zone and severity level,
   rather than forwarding broadly and relying on the downstream system to filter.

4.2. An alerting profile feeding an ITSM-facing problem notification **must not** include
   `MONITORING_UNAVAILABLE` severity unless that downstream system is specifically designed to handle
   monitoring-infrastructure outages as distinct from application and infrastructure Problems.

4.3. A problem notification **must** be named for its target system and its scoping alerting profile
   together (for example, "ServiceNow brooks-lab - Spark Observability"), not for the Dynatrace feature
   that produces it.

4.4. Two problem notifications whose alerting profiles can both match the same Problem **must** use
   mutually exclusive management-zone or tag filters, so one Problem is never forwarded to the same
   downstream system twice under two different identities.

4.5. A deep link to one specific Problem or Settings object **should not** be relied on as a durable
   reference in documentation or runbooks; link to the owning list view instead, and describe how to
   filter or search it, since per-object links on this class of tenant are not guaranteed to resolve.

### 5. Configuration as Code

5.1. Tenant configuration expressible as a Settings 2.0 object — management zones, alerting profiles,
   problem notifications, OpenPipeline pipelines — **must** be defined in Ansible, Terraform, or both,
   not left as UI-only configuration treated as the system of record.

5.2. When both Ansible and Terraform can deploy the same object, its JSON/YAML representation **must**
   be one shared source file that both read, not two independently maintained copies that can drift
   from each other.

5.3. A change to tenant configuration **should** be validated with a read-only diff (`terraform plan`,
   or an equivalent dry-run compare) before it is applied, and that diff **must** be read in full — an
   apply **must not** proceed past an unexplained, unrelated change surfaced in the same plan.

5.4. An infrastructure-as-code change **should** be scoped to apply only its intended resources (for
   example, Terraform's `-target`) when the same plan surfaces unrelated drift that has not yet been
   investigated, rather than applying everything the plan shows.

## Commentary

Statement 2.3 is the one most worth remembering on its own: a correctly computed source entity is not
enough by itself, because entity remapping defaults to enabled and can silently override it. The two
are a pair, not alternatives — setting `dt.source_entity` without also disabling remapping on that
processor looks correct in the processor's own configuration while still failing in production, which
is exactly how it was found here (see
[DT_Problems_to_SN_Event.md](../dynatrace/docs/DT_Problems_to_SN_Event.md) and
[SGO-Dynatrace_Enhancements.md](../servicenow/docs/Log_to_Incident/SGO-Dynatrace_Enhancements.md)).

Statement 3.4's fail-visible pairing exists because enrichment failures are otherwise invisible by
construction: the monitor that depends on the enrichment simply never fires the way it's supposed to,
and nothing tells you why. A second monitor whose matcher is the logical negation of the first's
enrichment condition turns that silence into a Problem.

Statements 5.3 and 5.4 come from the same incident: a `terraform plan` run to apply an unrelated,
intended change surfaced a second, pre-existing drifted resource in the same plan. Applying the whole
plan would have pushed that unrelated, not-yet-understood change live as a side effect. Scoping the
apply to the intended resources kept the two concerns separate.

## References

1. [TPGs for TPGs — meta-standard](../../../meta-standards/tpgs-for-tpgs.md)
2. [Observability — Service Management Documentation](../servicenow/docs/Log_to_Incident/Observability%20-%20Service%20Management%20Documentation.tpg.md)
3. [DT_Problems_to_SN_Event.md](../dynatrace/docs/DT_Problems_to_SN_Event.md)
4. [SGO-Dynatrace_Enhancements.md](../servicenow/docs/Log_to_Incident/SGO-Dynatrace_Enhancements.md)
5. [Terraform README — OpenPipeline resources and `terraform plan`/`apply` workflow](../../automation/terraform/README.md)
6. [standalone-short-log4j2-openpipeline.json.j2](../dynatrace/integrations/standalone-short-log4j2-openpipeline.json.j2) and [k8s-short-log4j2-openpipeline.json.j2](../dynatrace/integrations/k8s-short-log4j2-openpipeline.json.j2) — reference Davis processors demonstrating Statements 2.2, 2.3, 3.1–3.4
