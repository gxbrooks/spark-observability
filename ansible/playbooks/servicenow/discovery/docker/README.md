# Phase 3 — Docker discovery (Lab3 observability stack)

Discovers Docker containers from **`DOCKER_HOSTS`** in `vars/variables.yaml` into CMDB.

## Registry

| Variable | Purpose |
| -------- | ------- |
| `DOCKER_PRIMARY_HOST` | Registry key for the managed host (`lab3-observability`) |
| `DOCKER_HOSTS` | Host entries: `cmdb_host_name`, `location`, `ansible_host`, `managed` |

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
