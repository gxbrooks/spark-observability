#!/bin/bash
# Script to diagnose Docker/K8s registry and image issues

echo "=== Checking Docker Service ==="
sudo systemctl status docker | head -20

echo "=== Checking Docker Registry ==="
docker ps | grep registry
if [ $? -ne 0 ]; then
  echo "Docker registry not running! Starting it..."
  docker run -d -p 5000:5000 --restart=always --name registry registry:2
else
  echo "Registry is running."
fi

echo "=== Checking Registry Contents ==="
curl -s localhost:5000/v2/_catalog | jq .

echo "=== Checking for Spark Images ==="
docker images | grep spark

echo "=== Checking Kubernetes Pods ==="
kubectl get pods -n spark
kubectl get svc -n spark

echo "=== Checking Pod Image Pull Status ==="
kubectl describe pods -n spark | grep -E "Image:|Failed|Back-off"

echo "=== Checking Node Status ==="
kubectl get nodes
kubectl describe nodes | grep -i "kubelet"

echo "=== Checking Registry Config ==="
kubectl get configmap local-registry-config -n spark -o yaml
