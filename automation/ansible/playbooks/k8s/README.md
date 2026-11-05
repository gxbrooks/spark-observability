# Kubernetes playbooks

Service-management playbooks for the lab Kubernetes cluster. Hadoop HDFS is a nested module in `hadoop/`. Task playbooks that those verbs call live in `tasks/`.

## Service-management playbooks

| Playbook | Role |
| :--- | :--- |
| `install.yml` | Install kubelet, kubeadm, kubectl, CNI plugins; initialize the control plane |
| `start.yml` | Start containerd and kubelet, configure networking, join workers, assign Pod CIDRs |
| `diagnose.yml` | Cluster and node health, certificates, CNI, swap, Flannel |
| `test.yml` | Scheduler smoke and Spark/HDFS pod listing |
| `stop.yml` | Stop kubelet and containerd (workers first, then control plane) |
| `uninstall.yml` | Remove Kubernetes packages and restore host state |

## Task playbooks (`tasks/`)

| Playbook | Role |
| :--- | :--- |
| `provision-admin-kubeconfig.yml` | Copy `/etc/kubernetes/admin.conf` to every node in `k8s_nodes` |
| `regenerate-k8s-certs.yml` | Rebuild control-plane certificates when hostnames or SANs change |
| `configure-firewall.yml` | Kubernetes-aware UFW rules (`k8s_manage_ufw=true`) |
| `reset-k8s.yml` | Destructive `kubeadm reset` on all nodes |

HDFS representations are in `k8s/hadoop/` at the repository root. Use `hadoop/deploy.yml` and the other Hadoop service-management playbooks to apply them.

## Usage

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/k8s/install.yml
ansible-playbook -i inventory.yml playbooks/k8s/start.yml
ansible-playbook -i inventory.yml playbooks/k8s/diagnose.yml
ansible-playbook -i inventory.yml playbooks/k8s/test.yml
ansible-playbook -i inventory.yml playbooks/k8s/stop.yml
```

## Nested modules

- `hadoop/` — HDFS NameNode and DataNode on Lab3
