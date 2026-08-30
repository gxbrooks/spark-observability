# Hadoop HDFS playbooks

Service-management playbooks for HDFS on Kubernetes. Manifests live in `k8s/hadoop/` at the repository root.

## Service-management playbooks

| Playbook | Role |
| :--- | :--- |
| `deploy.yml` | Create namespace, ConfigMap, NameNode, DataNode, and NodePort exposure |
| `start.yml` | Scale NameNode and DataNode to one replica |
| `diagnose.yml` | Report namespace, pods, services, StatefulSets, and Deployments |
| `stop.yml` | Scale DataNode and NameNode to zero |
| `uninstall.yml` | Delete HDFS resources, namespace, and staged local copies |

## Usage

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/k8s/hadoop/deploy.yml
ansible-playbook -i inventory.yml playbooks/k8s/hadoop/start.yml
ansible-playbook -i inventory.yml playbooks/k8s/hadoop/diagnose.yml
ansible-playbook -i inventory.yml playbooks/k8s/hadoop/stop.yml
```

## Endpoints

- In-cluster: `hdfs://hdfs-namenode.hdfs.svc.cluster.local:9000`
- Client NodePort (Lab3): `hdfs://Lab3.lan:30900`
- NameNode UI NodePort: `http://Lab3.lan:30970`

## Prerequisites

- Kubernetes cluster running (`playbooks/k8s/start.yml`)
- `kubectl` configured on the `hadoop` inventory host (Lab3)
- Image `apache/hadoop:3.3.6`
