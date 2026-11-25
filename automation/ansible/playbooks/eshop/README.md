# eShop (queue-centric demo application)

Deploys [dotnet/eShop](https://github.com/dotnet/eShop) (MIT) on the lab Kubernetes cluster so
Dynatrace and ServiceNow Event Management can be studied against an application whose order
flow runs entirely on RabbitMQ integration events.

## Layout

| Path | Role |
|---|---|
| `automation/ansible/playbooks/eshop/` | Service-management playbooks (this directory) |
| `common/vars.yml` | Pinned upstream commit, registry, node placement, NodePorts, load rate |
| `k8s/eshop/*.yaml.j2` | Kubernetes representations (backing services, .NET services, load generator) |
| `eshop/patches/*.patch` | Lab changes applied to upstream before building (see `eshop/README.md`) |
| `eshop/loadgen/loadgen.py` | Order load generator; also the end-to-end check used by `test.yml` |
| `vars/secrets.yaml` → `eshop:` | Credentials (template in `vars/secrets.example.yaml`) |
| `~/repos/eShop` | Upstream source checkout (build input) |

## Placement

Lab3 carries no load-bearing components (it only serves images from `Lab3.lan:5000`).

| Node | Workloads |
|---|---|
| lab2 (`eshop_data_node`) | postgres (pgvector), redis (Valkey), rabbitmq, order-processor, payment-processor |
| lab1 (`eshop_app_node`) | identity-api, catalog-api, ordering-api, basket-api, webhooks-api, webapp, loadgen |

Every integration event therefore crosses Lab1 ↔ Lab2. RabbitMQ uses one direct exchange,
`eshop_event_bus`, with one queue per subscriber: `Basket`, `Catalog`, `Ordering`,
`OrderProcessor`, `PaymentProcessor`, `Webhooks`, `Ordering.webapp`.

## Playbooks

```bash
cd automation/ansible
ansible-playbook -i inventory.yml playbooks/eshop/build.yml      # images -> Lab3.lan:5000
ansible-playbook -i inventory.yml playbooks/eshop/deploy.yml     # identities + manifests
ansible-playbook -i inventory.yml playbooks/eshop/test.yml       # pass/fail, places 1 order
ansible-playbook -i inventory.yml playbooks/eshop/diagnose.yml   # test checks + deeper evidence
ansible-playbook -i inventory.yml playbooks/eshop/check.yml      # drift vs k8s/eshop (read-only)
ansible-playbook -i inventory.yml playbooks/eshop/stop.yml       # scale to 0, reverse order
ansible-playbook -i inventory.yml playbooks/eshop/start.yml      # scale to 1, restarts identity-api
ansible-playbook -i inventory.yml playbooks/eshop/undeploy.yml   # delete namespace (-e eshop_purge_data=true)
```

Prerequisite: nodes must pull from the plain-HTTP registry; see `playbooks/spark/registry/deploy.yml`
(containerd 2.x also needs the transfer-service `config_path`).

## Identities

`tasks/apply-identities.yml` (run by `deploy.yml`) builds Secret `eshop-credentials` from
`vars/secrets.yaml`:

- PostgreSQL superuser password and per-database connection strings (`catalogdb`, `identitydb`,
  `orderingdb`, `webhooksdb`). Postgres reads the password only when initialising an empty data
  directory; after changing it, run `undeploy.yml -e eshop_purge_data=true`, then `deploy.yml`.
- RabbitMQ user/password (created by the broker at start; its storage is ephemeral).
- Secret for the `loadgen` OIDC client (resource-owner password grant) added by
  `eshop/patches/identity-loadgen-client.patch`.
- The seeded eShop users: the load generator orders as `LOADGEN_USERNAME` (`alice`); `test.yml`
  and `diagnose.yml` order as `CHECK_USERNAME` (`bob`), so the check can tell its own order apart.
  eShop seeds both with password `Pass123$`.

## Duende IdentityServer licence

Identity.API uses Duende IdentityServer 8.x without a licence key ("trial mode"). In v8 that mode
has no request limit, no expiry and no shutdown; it logs a missing-licence error roughly every 30
minutes. `start.yml` still restarts identity-api when it is already running, as a safeguard for
future versions; this also regenerates its in-memory signing key, so existing tokens and browser
sessions end (the load generator re-authenticates). `diagnose.yml` counts licence log lines.

## Endpoints

- Store: `http://lab1.lan:30580`
- Identity: `http://lab1.lan:30581` (token issuer; browsers, APIs and loadgen all use this URL)
- RabbitMQ management: `http://lab1.lan:30582`

Browser sign-in runs over plain HTTP on a non-localhost name; browsers may drop the OIDC
correlation cookies and refuse the login. Browsing the catalogue and the load generator are not
affected.

## Observability (Dynatrace and ServiceNow)

| Signal | Where it is configured | Result |
|---|---|---|
| RabbitMQ per-queue metrics | `metrics.dynatrace.com/*` annotations on the rabbitmq pod (`k8s/eshop/infra.yaml.j2`); `openMetricsPipelineEnabled` in `specifications/dynatrace/integrations/k8s-monitoring/cloud_monitoring-anomaly-enabled.json` | `rabbitmq_queue_*` metrics split by `queue`, bound to the rabbitmq workload |
| Queue backlog / no consumer | `eshop-rabbitmq-queue-{backlog,no-consumer}-metric-event.json.j2` (Ansible: `apply-eshop-queue-metric-events.yml`; Terraform: `dynatrace_settings.tf`) | Davis problems per queue; ServiceNow binds them to the queue CI |
| WARN/ERROR/CRITICAL logs | Single-line .NET console logs (`apps.yaml.j2`); OpenPipeline `eshop-dotnet-log-alerts-openpipeline.json.j2` + routing entry | One Davis problem per workload + logger category + level |
| Kubernetes anomalies and events | Management zone rules for namespace `eshop` (workloads, namespace, process groups); `eventProcessingActive` | Workload, node and cluster problems flow to ServiceNow |
| CMDB | `playbooks/servicenow/discovery/rabbitmq/` | `cmdb_ci_appl_rabbitmq` + one `cmdb_ci_appl_rabbitmq_queue` per queue, consumer `Depends on` relations |

Stress scenario (saturation plus three injected faults, then a full restore):

```bash
ansible-playbook -i inventory.yml playbooks/eshop/test.yml --tags stress -e eshop_stress_minutes=12
```

## Load generation

`loadgen` places `eshop_loadgen_orders_per_minute` orders per minute (default 2) through
Ordering.API. Each order runs the saga: `OrderStarted` → grace period (order-processor, ~1 min)
→ `AwaitingValidation` → catalog stock check → `StockConfirmed` → payment-processor →
`Paid`. Change the rate live with
`kubectl -n eshop set env deploy/loadgen ORDERS_PER_MINUTE=30` (0 pauses ordering).

**Capacity ceiling: about 3 orders/minute.** ordering-api consumes the `Ordering` queue one
message at a time, and upstream eShop deliberately sleeps 10 s in its `SetStockConfirmed`,
`SetStockRejected` and `SetPaid` command handlers ("simulate a work time"), two of which run per
order. Above ~3 orders/min the `Ordering` queue's unacknowledged count grows without bound, and
order-processor amplifies it by re-publishing `GracePeriodConfirmed` every 30 s for orders still
`Submitted`. This is a ready-made consumer-saturation scenario:
`kubectl -n eshop set env deploy/loadgen ORDERS_PER_MINUTE=6`. Recover by setting the rate back;
a large backlog takes ~10–20 s per stuck order to drain.

Useful queue experiments: scale `payment-processor` to 0 (its queue backs up while the store
looks healthy), or scale `rabbitmq` to 0 (every service loses the bus).
