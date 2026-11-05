# Docker Playbooks

⚠️ **DEPRECATED**: Use of Docker is currently deprecated in favor of containerd for Kubernetes deployments.

These playbooks manage **Docker Engine only on the observability host** (inventory group `observability`, e.g. Lab3), for the Docker Compose stack.

**Note**: For Kubernetes deployments, containerd is the container runtime. Spark deployment (`playbooks/spark/deploy.yml`) still runs `docker build`, a local registry on port 5000, and `docker push` on **kubernetes_master** (Lab2) unless you change that workflow—those steps are not covered by the playbooks in this directory.

## Available Playbooks

- `install_docker.yml` - Installs Docker on the observability host
- `start_docker.yml` - Starts the Docker service and registry
- `stop_docker.yml` - Stops the Docker service
- `restart_docker.yml` - Restarts the Docker service
- `status_docker.yml` - Displays detailed Docker status information
- `diagnose_docker.yml` - Provides comprehensive diagnostics about Docker installation

## Usage

### Install Docker

```bash
ansible-playbook -i inventory.yml playbooks/docker/install_docker.yml
```

### Start Docker

```bash
ansible-playbook -i inventory.yml playbooks/docker/start_docker.yml
```

### Stop Docker

```bash
ansible-playbook -i inventory.yml playbooks/docker/stop_docker.yml
```

### Restart Docker

```bash
ansible-playbook -i inventory.yml playbooks/docker/restart_docker.yml
```

### Check Docker Status

```bash
ansible-playbook -i inventory.yml playbooks/docker/status_docker.yml
```

### Diagnose Docker Issues

```bash
ansible-playbook -i inventory.yml playbooks/docker/diagnose_docker.yml
```

## Notes

- Install/start/stop/diagnose/uninstall target **`observability`** only (not Lab1/Lab2).
- The playbooks include error checking and diagnostic information.
