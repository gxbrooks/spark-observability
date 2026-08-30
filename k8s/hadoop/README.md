# Hadoop HDFS Kubernetes representations

Desired-state manifests for HDFS on the lab Kubernetes cluster. Playbooks in `ansible/playbooks/k8s/hadoop/` apply these files; they are not stored under the Ansible tree.

## Files

| File | Purpose |
| :--- | :--- |
| `hadoop-namenode.yaml` | NameNode StatefulSet, NodePort service (`30900` RPC, `30970` UI), headless service. Pinned to **lab3**. |
| `hadoop-datanode.yaml` | DataNode Deployment and ClusterIP service. Pinned to **lab3**. |
| `hadoop-configmap.yaml.j2` | Namespace plus ConfigMap (`core-site.xml`, `hdfs-site.xml`). Instantiates `HDFS_DEFAULT_FS`. |

## Client URI

Hosts outside the cluster use the NameNode NodePort on Lab3: `hdfs://Lab3.lan:30900`. In-cluster workloads use `hdfs://hdfs-namenode.hdfs.svc.cluster.local:9000`.

## Apply

```bash
cd ansible
ansible-playbook -i inventory.yml playbooks/k8s/hadoop/deploy.yml
ansible-playbook -i inventory.yml playbooks/k8s/hadoop/start.yml
ansible-playbook -i inventory.yml playbooks/k8s/hadoop/diagnose.yml
```
