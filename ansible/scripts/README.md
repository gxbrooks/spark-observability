# Ansible Support Scripts

This directory contains utility scripts to support the Ansible deployment and operations.

## Available Scripts

### diagnostics_docker_k8s.sh

A diagnostic tool for Docker and Kubernetes integration issues. It helps troubleshoot common problems with:

- Docker service status
- Docker registry availability and content
- Spark image availability
- Kubernetes pod and service status
- Image pull issues
- Kubernetes node status
- Registry configuration

**Usage:**
```bash
./diagnostics_docker_k8s.sh
```

Run this script when:
- Pods are stuck in ImagePullBackOff state
- Deployments fail to start
- Registry connectivity issues occur
- Docker image building problems arise

The script provides a comprehensive overview of the system state to help diagnose and resolve issues quickly.

### launch_pyspark_ipython.sh

**DEPRECATED - REPLACED BY ANSIBLE PLAYBOOK**

This script launches an IPython shell with PySpark in a Kubernetes pod. It has been replaced by a more robust Ansible playbook:

**Replacement Playbook:**
```bash
cd /home/gxbrooks/repos/elastic-on-spark/ansible
ansible-playbook playbooks/spark/launch_ipython.yml
```

**Manual Connection:**
If you prefer to connect manually after creating the pod:
```bash
# Create pod without interactive shell
ansible-playbook playbooks/spark/launch_ipython.yml -e "launch_shell=false allow_interactive=false"

# Then connect manually 
kubectl exec -it pyspark-ipython -n spark -- bash -c 'PYSPARK_DRIVER_PYTHON=ipython3 PYSPARK_DRIVER_PYTHON_OPTS="" SPARK_DRIVER_OPTS="-Xlog:gc:stdout" pyspark --master local[*] --conf spark.driver.extraJavaOptions="-Xlog:gc:stdout" --conf spark.eventLog.enabled=true --conf spark.eventLog.dir="/mnt/spark-events"'
```

The Ansible playbook provides more options and better integration with the rest of the deployment:
- Configurable resource allocation
- Option to launch without interactive shell
- Custom pod naming
- Better error handling and validation
- Proper volume mounts for Spark events directory
- Automatic creation of required directories

Run this script when:
- Testing a new deployment of the PySpark IPython environment
- Verifying fixes to the PySpark configuration
- Ensuring the local mode execution works correctly

The script provides validation that the PySpark IPython environment is working properly.

### New Interactive Launch Script

For a more convenient developer experience, check out the new interactive launch script:

```bash
# Located in the linux directory
/home/gxbrooks/repos/elastic-on-spark/linux/launch_ipython.sh
```

This script:
- Creates a PySpark IPython pod if it doesn't exist
- Launches an interactive IPython shell with PySpark in the current terminal
- Configures proper GC logging to files instead of stdout
- Uses the shared NFS mount for event logging
- Provides clear instructions for cleanup

For more information, see the [Spark Deployment Consolidation](../../docs/SPARK_DEPLOYMENT_CONSOLIDATION.md) documentation.

See the documentation in `docs/RUNNING_ANSIBLE_PLAYBOOKS.md` for more details.
