# eShop in CSDM — design record

Living doc. Started 2026-11-26. Spec: `specifications/servicenow/regions/brooks-lab/eshop.csdm.yaml`
(applied with `playbooks/servicenow/csdm/deploy.yml`). Diagrams and tagging snippets:
`eShop_Architecture.pptx` (generator: `tools/build_eshop_architecture_pptx.py`).

## Model

| Layer | Records |
| --- | --- |
| Business application | eShop |
| Business services (one per functional component) | eShop Storefront, eShop Identity, eShop Catalog, eShop Ordering, eShop Payment Processing, eShop Partner Notifications |
| Business service offerings | `<service> - Production` for each |
| Technology management services | PostgreSQL, RabbitMQ, Kubernetes Platform (shared with Spark) |
| Technology management offerings | PostgreSQL - Production, RabbitMQ - Production, Kubernetes Platform - Production |
| Dynamic CI groups | RabbitMQ Queues (brooks-lab) → RabbitMQ - Production; Kubernetes Clusters (brooks-lab) → Kubernetes Platform - Production |
| Service instances (tag-based, one per workload) | WebApp, Basket API, Redis → Storefront; Identity API → Identity; Catalog API → Catalog; Ordering API, Order Processor → Ordering; Payment Processor → Payment Processing; Webhooks API → Partner Notifications; eShop PostgreSQL → PostgreSQL TMO; eShop RabbitMQ → RabbitMQ TMO; eShop Load Generator → Kubernetes Platform TMO |

Decisions:

- **No `depends_on`** between service instances or to platforms. The lab wants to see which
  dependencies the SGC for Dynatrace SaaS brings over on its own.
- **Redis** stays with the Storefront (it is the basket's private store), not a technology service.
- **Load generator** is lab test traffic, so it sits under the Kubernetes Platform offering. It is not in any business offering, so its alerts never suggest customer impact.
- **Service instances under a technology offering** need no sn-sync change. `link_offerings` resolves the offering by name in `service_offering`, and that table holds both kinds of offering.

## Binding chain (pods are too ephemeral to alert on)

**ServiceNow side:** each workload and its pod template carry `servicenow.com/service-instance: eShop-<Name>`
(`eshop_service_instances` in `playbooks/eshop/common/vars.yml`).
1. KVA copies the label to `cmdb_key_value` for the Deployment, ReplicaSet and pod CIs.
2. Tag-based Service Mapping adds those CIs to the service instance (`svc_ci_assoc`).

**Dynatrace side:** the eShop log pipeline maps the workload name to the same value (`sn-service-instance`)
and raises the Davis event on the cloud application, which is the workload.

**Where they meet:** the `ResolveApplicationService` enrichment step resolves `eShop-Catalog-API` to the service instance
"eShop Catalog API".

## Infrastructure issue vs. impacted application services

The problem: an incident has one `service_offering` (and one `business_service` and one `cmdb_ci`),
but a queue or database failure impacts several business offerings. The lab's working answer is
built from out-of-box ServiceNow pieces. Each one still has to be verified in the lab.

1. **The cause gets the incident.** The incident's `service_offering` is the technology offering that owns the failed
   component, for example RabbitMQ - Production, and its `cmdb_ci` is the component itself, for example the queue CI.
   - The platform team owns that incident, and its SLA is the platform's.
2. **Business impact comes from the service map, not from that single field.**
   - On the incident: the Impacted Services/CIs list (`task_cmdb_ci_service`) is filled from the affected CI through the service map. It shows every service instance and offering that contains the CI or depends on it.
   - In Event Management: the impact tree and service health show the same information.
3. **One cause, one incident.** Alert grouping (CMDB-based or time-based) makes the queue alert primary. Downstream alerts, such as ordering-api errors, become secondary alerts in that group, and their CIs land in Affected CIs (`task_ci`).
4. **Per-offering tickets only when needed.** If a business offering's owners need their own record and SLA, use the Major Incident process. The platform incident is the parent; each business offering gets a child incident with its own `service_offering`.
5. **Root cause** goes to a Problem record linked to the parent.

Points 2 and 3 need the CMDB to connect the failed component to the business service instances.

**What exists today:**
- RabbitMQ discovery relates each queue to its consumer's Deployment CI (Depends on::Used by).
- Tag-based mapping puts the Deployment into its service instance.

**Open lab questions:**
- Does impact calculation follow `queue ← Deployment ∈ service instance`, or does the queue itself have to be a member of the service instance?
- What relationships does the SGC for Dynatrace SaaS add, for example service-to-service calls and process-to-database edges?
