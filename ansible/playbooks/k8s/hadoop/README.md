# Hadoop Kubernetes Playbooks

This directory contains Ansible playbooks for deploying and managing Hadoop HDFS on Kubernetes.

## Playbooks

### `deploy_hadoop.yml`
Deploys Hadoop HDFS (NameNode and DataNode) on Kubernetes:
- Creates Hadoop namespace (`hdfs`)
- Deploys NameNode StatefulSet
- Deploys DataNode Deployment
- Configures Hadoop services and ConfigMaps

### `start_hadoop.yml`
Starts Hadoop services on Kubernetes:
- Scales up NameNode StatefulSet to 1 replica
- Scales up DataNode Deployment to 1 replica
- Waits for services to be ready

### `stop_hadoop.yml`
Stops Hadoop services on Kubernetes:
- Scales down DataNode Deployment to 0 replicas
- Scales down NameNode StatefulSet to 0 replicas
- Waits for pods to terminate

### `status_hadoop.yml`
Checks the status of Hadoop services:
- Shows namespace status
- Lists all Hadoop pods
- Shows services, StatefulSets, and Deployments
- Displays service URLs

### `uninstall_hadoop.yml`
Completely removes Hadoop from Kubernetes:
- Deletes all Hadoop resources
- Removes the Hadoop namespace
- Cleans up local configuration files

## Configuration Files

### `hadoop-namenode.yaml`
Kubernetes configuration for Hadoop NameNode:
- StatefulSet for persistent storage
- Service for external access
- Headless service for internal communication

### `hadoop-datanode.yaml`
Kubernetes configuration for Hadoop DataNode:
- Deployment for scalable storage
- Service for internal communication

### `hadoop-configmap.yaml.j2`
Jinja2 template for Hadoop configuration:
- Core-site.xml with HDFS default filesystem
- Hdfs-site.xml with NameNode and DataNode settings
- Uses variables from `variables.yaml`

## Variables

The playbooks use variables from `variables.yaml` with the `hadoop` context:

- `HADOOP_NAMENODE`: NameNode service name and port
- `HADOOP_CONF_DIR`: Hadoop configuration directory
- `HADOOP_HOME`: Hadoop installation directory
- `HDFS_DEFAULT_FS`: HDFS default filesystem URI
- `HADOOP_NAMESPACE`: Kubernetes namespace for Hadoop
- `HADOOP_NAMENODE_SERVICE`: NameNode service name
- `HADOOP_DATANODE_SERVICE`: DataNode service name

## Usage

1. **Deploy Hadoop:**
   ```bash
   ansible-playbook -i inventory.yml ansible/playbooks/k8s/hadoop/deploy_hadoop.yml
   ```

2. **Start Hadoop:**
   ```bash
   ansible-playbook -i inventory.yml ansible/playbooks/k8s/hadoop/start_hadoop.yml
   ```

3. **Check Status:**
   ```bash
   ansible-playbook -i inventory.yml ansible/playbooks/k8s/hadoop/status_hadoop.yml
   ```

4. **Stop Hadoop:**
   ```bash
   ansible-playbook -i inventory.yml ansible/playbooks/k8s/hadoop/stop_hadoop.yml
   ```

5. **Uninstall Hadoop:**
   ```bash
   ansible-playbook -i inventory.yml ansible/playbooks/k8s/hadoop/uninstall_hadoop.yml
   ```

## Service URLs

After deployment, Hadoop services are available at:

- **NameNode Web UI**: `http://<hostname>:9870`
- **NameNode RPC**: `<hostname>:9000`
- **DataNode**: `<hostname>:9864`

## Prerequisites

- Kubernetes cluster running
- `kubectl` installed and configured
- Ansible with Kubernetes collection
- Docker images: `apache/hadoop:3.3.6`

## Notes

- The Hadoop configuration uses Kubernetes service names for internal communication
- NameNode uses StatefulSet for persistent storage
- DataNode uses Deployment for scalability
- All configuration is templated using variables from `variables.yaml`
