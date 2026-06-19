# CSDM specification format

This document defines the YAML specification format for ServiceNow **Common Service Data Model (CSDM)** objects deployed by `playbooks/servicenow/csdm/deploy.yml`.

## Why YAML

Specifications are YAML lists rather than CSV or JSON because:

- Authors already use YAML for Ansible playbooks and inventory.
- Nested structures (entry points, expand rules) stay readable without extra columns or escape rules.
- Files support Jinja templating so shared values from generated context files (for example `{{ SPARK_MASTER_HOST }}`) resolve at deploy time.

CSV is workable for flat tables but becomes awkward for relationships and repeated entry-point blocks. JSON lacks comments and is harder to edit by hand.

## File location and registration

| Item | Convention |
|------|------------|
| Default path | `<application-playbook-dir>/servicenow/servicenow.yaml` |
| Registration | Add a path relative to `ansible/playbooks/` to `sn_csdm_spec_files` in `csdm/common/vars.yml` |
| Processing | Deploy loads each file with `lookup('template', ...)`, parses YAML, then creates or updates records |

Example registration:

```yaml
sn_csdm_spec_files:
  - spark/servicenow/servicenow.yaml
```

## Top-level sections

Each `servicenow.yaml` file **may** contain zero or more of:

| Section | CMDB table | Purpose |
|---------|------------|---------|
| `business_applications` | `cmdb_ci_business_app` | Top-level business application (CSDM) |
| `business_services` | `cmdb_ci_service` | Business service under a business application |
| `application_services` | `cmdb_ci_service_discovered` | Application service for Service Mapping |

Deploy order within a file: business applications → business services → application services.

## Referencing shared configuration

Specifications **may** reference context variables from generated Ansible vars files using Jinja:

```yaml
entry_points:
  - table: cmdb_ci_ip_service
    name: "{{ SPARK_MASTER_HOST }}:{{ SPARK_MASTER_PORT }}"
    port: "{{ SPARK_MASTER_PORT | string }}"
```

Rules:

- Use context variables only for values **shared across multiple consumers** (see `vars/docs/Context_Variable_Best_Practice.md`).
- Keep application-specific names and descriptions in `servicenow.yaml`.
- Ensure the deploy playbook loads the generated context file that defines referenced variables (for example `servicenow_ansible_vars.yml`).

## business_applications

List of business application objects.

| Attribute | Required | Meaning |
|-----------|----------|---------|
| `name` | yes | CMDB `name` — unique lookup key |
| `short_description` | recommended | Human-readable description |
| `operational_status` | optional | ServiceNow choice value (`"1"` = Operational) |
| `active` | optional | `"true"` / `"false"` for business applications |

Example:

```yaml
business_applications:
  - name: Data and Analytic Services
    short_description: Data processing and analytics platform services
    operational_status: "1"
    active: "true"
```

Any additional table fields supported by the Table API **may** be included; they are passed through on create and patch (except `name`).

## business_services

List of business service objects.

| Attribute | Required | Meaning |
|-----------|----------|---------|
| `name` | yes | CMDB `name` — unique lookup key |
| `short_description` | recommended | Human-readable description |
| `operational_status` | optional | ServiceNow choice value |
| `parent_business_application` | recommended | `name` of a business application in the same file (creates **Contains::Contained by** relationship: BA → BS) |

Example:

```yaml
business_services:
  - name: Apache Spark
    short_description: Distributed data processing cluster
    operational_status: "1"
    parent_business_application: Data and Analytic Services
```

## application_services

List of application service definitions. Each item becomes one or more CMDB application service records.

| Attribute | Required | Meaning |
|-----------|----------|---------|
| `name` | yes | CMDB `name`; **may** include `{host}` or `{host_lower}` when using `expand` |
| `short_description` | recommended | Description; supports `{host}` / `{host_lower}` substitution |
| `operational_status` | optional | ServiceNow choice value |
| `parent_business_service` | yes | `name` of a business service in the same file (creates **Contains::Contained by**: BS → app service) |
| `entry_points` | recommended | List of entry-point CI definitions (see below) |
| `discover` | optional | When `true`, deploy triggers Service Mapping vertical discovery after registration (async) |
| `expand` | optional | Repeat this definition for each host in an Ansible inventory group |

### expand

Use when one specification row represents many instances (for example one Spark worker per Kubernetes worker node):

```yaml
expand:
  inventory_group: kubernetes_workers
```

For each host in the group, `{host}` is replaced with the inventory hostname (for example `Lab1`) and `{host_lower}` with lowercase (for example `lab1`).

### entry_points

Each entry point links the application service to a CI Service Mapping uses to start top-down discovery (**Depends on::Used by**: app service → entry CI).

| Attribute | Required | Meaning |
|-----------|----------|---------|
| `table` | yes | `cmdb_ci_ip_service` or `cmdb_ci_linux_server` |
| `name` | conditional | For `cmdb_ci_ip_service`: CI name, typically `host:port` |
| `lookup_name` | conditional | For `cmdb_ci_linux_server`: existing Linux server CI name (supports `{host_lower}`) |
| `port` | optional | Port field for IP service CIs |
| `short_description` | optional | Description for IP service CIs |

**IP service** entry points are created or updated if missing. **Linux server** entry points must already exist (from horizontal Discovery); deploy fails if the CI is missing.

Example (master with two NodePorts):

```yaml
application_services:
  - name: Spark Master
    short_description: Spark master — client and Web UI entry via NodePort
    operational_status: "1"
    parent_business_service: Apache Spark
    discover: true
    entry_points:
      - table: cmdb_ci_ip_service
        name: "{{ SPARK_MASTER_HOST }}:{{ SPARK_MASTER_PORT }}"
        port: "{{ SPARK_MASTER_PORT | string }}"
        short_description: Spark master client NodePort
      - table: cmdb_ci_ip_service
        name: "{{ SPARK_MASTER_HOST }}:{{ SPARK_MASTER_UI_NODEPORT }}"
        port: "{{ SPARK_MASTER_UI_NODEPORT | string }}"
        short_description: Spark master Web UI NodePort
```

Example (worker per inventory host):

```yaml
  - name: "Spark Worker ({host})"
    short_description: "Spark worker on {host} — entry via Linux server CI"
    operational_status: "1"
    parent_business_service: Apache Spark
    discover: true
    expand:
      inventory_group: kubernetes_workers
    entry_points:
      - table: cmdb_ci_linux_server
        lookup_name: "{host_lower}"
```

## Relationships created automatically

| Relationship | Type | Parent → Child |
|--------------|------|----------------|
| BA contains BS | Contains::Contained by | business application → business service |
| BS contains app service | Contains::Contained by | business service → application service |
| App service depends on entry | Depends on::Used by | application service → entry-point CI |

## Service Mapping vertical discovery

When `discover: true`:

1. Deploy ensures entry points are registered in `sa_m2m_service_entry_point` (via Service Mapping Operations REST API when needed).
2. Deploy calls `startDiscovery` for each application service.
3. Deploy **does not** wait for completion.

Use `csdm/diagnose.yml` to inspect:

- `process_status` on `cmdb_ci_service_discovered` (`1` = Discovered, `2` = In Progress on many instances)
- `service_status`
- Registered entry points in `sa_m2m_service_entry_point`

## Validation expectations

- Business service `parent_business_application` must match a `name` in `business_applications` in the same file (deployed earlier in the same run).
- Application service `parent_business_service` must match a `name` in `business_services`.
- Expanded application services require a non-empty Ansible inventory group.
- Linux server entry points require prior horizontal Discovery on target hosts.

## References

- ServiceNow CSDM documentation (Business Application, Business Service, Application Service)
- `playbooks/servicenow/csdm/README.md` — operational usage
- `vars/docs/Context_Variable_Best_Practice.md` — when to use context variables vs application-local specs
