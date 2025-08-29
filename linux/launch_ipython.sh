#!/bin/bash
#
# Interactive PySpark IPython launcher script
#
# This script launches a PySpark IPython environment in a Kubernetes pod.
# It first checks if the pod exists, creates it if necessary, and then
# connects to an interactive IPython shell with PySpark configured.
#
# The script handles error checking and provides useful feedback to the user.
#
# IMPORTANT: This script is designed to be used directly from the terminal.
# It uses the Ansible playbook with launch_shell=false to create the pod,
# then launches its own interactive shell. Don't run this script from within
# another Ansible playbook as it could cause shell nesting issues.
#
# Usage: ./launch_ipython.sh

# Color codes for pretty output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Exit on any error
set -e

# Print a header
echo -e "${GREEN}=== PySpark IPython Interactive Shell ===${NC}"

# Check if NFS mount is available on the host
if ! mountpoint -q /mnt/spark-events; then
    echo -e "${YELLOW}Warning: NFS mount /mnt/spark-events is not mounted on this host.${NC}"
    echo -e "${YELLOW}Event logs may not be accessible. Consider setting up the NFS mount first.${NC}"
    echo -e "${YELLOW}Run: ansible-playbook -i inventory.yml ansible/playbooks/nfs/install_nfs.yml${NC}"
    read -p "Continue anyway? (y/n): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Exiting. Please set up the NFS mount and try again.${NC}"
        exit 0
    fi
fi

# Check if a spark-ipython pod is already running
if kubectl get pod pyspark-ipython -n spark &>/dev/null; then
    echo -e "${YELLOW}PySpark IPython pod already exists. Using existing pod.${NC}"
else
    echo -e "${GREEN}Creating PySpark IPython pod...${NC}"
    # Create the pod using Ansible (launch_shell=false to create pod only, without launching an interactive shell)
    cd "$(dirname "$0")/../ansible"
    ansible-playbook playbooks/spark/launch_ipython.yml -e "launch_shell=false allow_interactive_param=false create_log_dir_skipped=true" || {
        echo -e "${YELLOW}Failed to create PySpark IPython pod. Please check the error messages above.${NC}"
        exit 1
    }
    
    echo -e "${GREEN}Waiting for pod to be ready...${NC}"
    # Wait for the pod to be ready
    kubectl wait --for=condition=Ready pod/pyspark-ipython -n spark --timeout=60s || {
        echo -e "${YELLOW}Timed out waiting for pod to be ready. Check pod status with: kubectl describe pod pyspark-ipython -n spark${NC}"
        exit 1
    }
fi

echo -e "${GREEN}Launching interactive IPython shell with PySpark...${NC}"
echo -e "${YELLOW}Note: To exit, press Ctrl+D or type 'exit' in the IPython shell${NC}"
echo -e "${YELLOW}When done, don't forget to clean up: kubectl delete pod pyspark-ipython -n spark${NC}"
echo -e "${GREEN}=======================================${NC}"

# Ensure log directory exists in the pod
echo -e "${GREEN}Ensuring log directory exists...${NC}"
kubectl exec pyspark-ipython -n spark -- bash -c "mkdir -p /opt/spark/logs && chmod 777 /opt/spark/logs" || {
    echo -e "${YELLOW}Warning: Could not create log directory in pod. GC logs may not be written correctly.${NC}"
}

# Launch IPython with PySpark in the current terminal
# Set GC logs to standard GC log files
echo -e "${GREEN}Connecting to pod's IPython shell...${NC}"

kubectl exec -it pyspark-ipython -n spark -- \
    bash -c 'PYSPARK_DRIVER_PYTHON=ipython3 \
             PYSPARK_DRIVER_PYTHON_OPTS="" \
             SPARK_DRIVER_OPTS="-Xlog:gc:file=/opt/spark/logs/gc.log:time" \
             pyspark \
             --master local[*] \
             --conf spark.driver.extraJavaOptions="-Xlog:gc:file=/opt/spark/logs/gc.log:time" \
             --conf spark.eventLog.enabled=true \
             --conf spark.eventLog.dir="/mnt/spark-events"'
EXEC_STATUS=$?

# Check if exec command succeeded
if [ $EXEC_STATUS -ne 0 ]; then
    echo -e "${YELLOW}IPython shell exited with an error (status code: $EXEC_STATUS).${NC}"
    echo -e "${YELLOW}Check the pod status with: kubectl describe pod pyspark-ipython -n spark${NC}"
else
    echo -e "\n${GREEN}IPython session ended normally.${NC}"
fi

echo -e "${YELLOW}To clean up the pod, run: kubectl delete pod pyspark-ipython -n spark${NC}"
echo -e "${YELLOW}Or to reconnect to this pod, simply run this script again.${NC}"
