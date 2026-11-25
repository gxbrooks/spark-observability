# RabbitMQ discovery (eShop broker)

Representations for ServiceNow CMDB discovery of the eShop RabbitMQ broker and its queues.
Playbooks: `automation/ansible/playbooks/servicenow/discovery/rabbitmq/`.
Terraform (configuration records only): `automation/terraform/servicenow/`.

## Why not the OOTB RabbitMQ patterns

The instance ships the "RabbitMQ Unix", "RabbitMQ Cluster Unix" and "RabbitMQ Queue" Discovery
patterns. They cannot discover this broker because it runs as a Kubernetes container:

* Identification requires the `beam.smp` parent process to be `rabbitmq-server`. In the official
  image `beam.smp` is the container's PID 1, so on the host its parent is `containerd-shim`; the
  fallback check reads the process owner, which on the host is `dnsmasq` (uid 999).
* Every step runs `sudo rabbitmqctl ...` on the host. `rabbitmqctl` exists only inside the
  container, and the AMQP ports live in the pod network namespace.
* No process classifier on the instance launches these patterns.

The Dynatrace Service Graph Connector imports no queue entities, and ServiceNow's Kubernetes
Visibility Agent stops at Deployments, Pods and containers.

## How it works instead

`start.yml` reads the RabbitMQ management API and sends the broker and its queues through the
Identification and Reconciliation Engine (IRE) with discovery source `RabbitMQ-API`, so the OOTB
identification rules, reconciliation and `Contains`/`Runs on` dependency rules apply exactly as
they would for pattern discovery. It then relates each queue to the Kubernetes Deployment CI of
its consumer (from the KVA) with `Depends on::Used by`, using the consumer connection's pod IP.

| File | Object |
|---|---|
| `sys_choice_discovery_source_rabbitmq_api.json` | Discovery source choice `RabbitMQ-API` on `cmdb_ci.discovery_source` (Ansible and Terraform) |
| `rabbitmq-ire-payload.json.j2` | IRE payload: host (by name), broker, queues, `Runs on` and `Contains` relations (Ansible, per run) |
