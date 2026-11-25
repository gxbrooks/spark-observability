# Terraform — ServiceNow configuration

Separate root module (own state `tfstate-default-servicenow-spark-observability`, same Kubernetes
backend and Lease locking as `../`), so Dynatrace/Elastic plans never need ServiceNow credentials.

Provider: `Mastercard/restapi` over the Table API. Each resource reads the same representation file
under `specifications/servicenow/` that the Ansible playbooks apply; `read_search` with
`results_key = "result"` unwraps the Table API envelope and `ignore_server_additions` limits drift
detection to the representation's fields.

| File | Object | Ansible counterpart |
|---|---|---|
| `discovery_rabbitmq.tf` | `cmdb_ci.discovery_source` choice `RabbitMQ-API` | `playbooks/servicenow/discovery/rabbitmq/deploy.yml` |

Procedural work (the RabbitMQ discovery run through the IRE) stays in Ansible (`start.yml`).

```bash
cd automation/terraform/servicenow
eval "$(scripts/sn-env.sh)"     # TF_VAR_SN_URL/USER/PASSWORD for the active instance (or SN_TARGET)
terraform init
terraform plan
```

Interchangeability (automation standard, Idempotency 4-6) was checked on Demo1, 2026-11-25:
Ansible created the record, Terraform imported and applied it, then `terraform plan` reported no
changes and Ansible's `deploy.yml` reported "matches its representation".
