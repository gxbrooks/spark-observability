# Phase 3 — Docker container discovery

Discovers Docker containers from **`DOCKER_HOSTS`** entries with **`container_discovery: true`** in `vars/variables.yaml` into CMDB.

## Registry

| Variable | Purpose |
| -------- | ------- |
| `DOCKER_HOSTS` | Host entries: `cmdb_host_name`, `location`, `ansible_host`, and capability flags (see below) |

Capability flags per entry (absent = false):

| Flag | Purpose |
| ---- | ------- |
| `discovery_docker_pattern` | `sn-discovery` joins `docker` group + Docker Pattern sudoers on this host (`discovery/install.yml`) |
| `container_discovery` | Sync running containers into CMDB via `docker/discover.yml` |

Location uses the same product-native pattern as K8s:

1. Containers link to Linux server CI (`host=lab3`)
2. Business rule `docker-inherit-location-from-host` copies `host.location` on insert/update

## Playbooks

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/deploy.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/discover.yml -e @../vars/secrets.yaml
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/test.yml -e @../vars/secrets.yaml
```

`discover.yml` syncs running containers, writes **`servicenow.io/*`** and **`com.docker.compose.*`** labels to **`cmdb_key_value`** (required for tag-based Service Mapping), retires container CIs whose `container_id` is no longer running, and deduplicates multiple CMDB rows that share the same container **name** on a host when only one matching container is running.

Retire stale containers and deduplicate by name (same cleanup steps as `discover.yml`, without upsert or label sync):

```bash
ansible-playbook -i inventory.yml playbooks/servicenow/discovery/docker/cleanup.yml -e @../vars/secrets.yaml
```

Tag-based SM instance configuration: [servicenow/docs/Tag_Based_Service_Mapping.md](../../../../servicenow/docs/Tag_Based_Service_Mapping.md).
