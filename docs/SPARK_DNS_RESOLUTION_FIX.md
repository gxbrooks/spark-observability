# Spark on Kubernetes DNS Resolution Fix

This document outlines the changes made to fix DNS resolution issues in the Spark on Kubernetes deployment.

## Problem Statement

The Spark Master was experiencing CrashLoopBackOff errors due to DNS resolution issues with `java.nio.channels.UnresolvedAddressException`. The deployment was unable to resolve its own hostname (`spark-master`).

## Solution Summary

1. Converted Spark Master deployment to a StatefulSet with a headless service
2. Updated DNS resolution in the entrypoint script with proper fallbacks
3. Enhanced network configuration in Spark settings
4. Created comprehensive health checks for monitoring

## Implementation Details

### 1. Kubernetes Configuration Changes

- **StatefulSet**: Spark Master now runs as a StatefulSet with predictable DNS names
- **Headless Service**: Added `spark-master-headless` service for better DNS resolution
- **Pod Hostname/Subdomain**: Configured for proper DNS entries with FQDN support

### 2. Entrypoint Script Enhancements

- **Role-based DNS handling**: Different handling for master, workers and history server
- **Multiple resolution methods**: Added fallback mechanisms for hostname resolution
- **Environment variable updates**: Set proper network-related environment variables

### 3. Spark Configuration Updates

- **Updated spark-defaults.conf**: Added network timeout settings and hostname configurations
- **Updated ConfigMap**: Using fully qualified domain names (FQDN) for all references

### 4. Monitoring & Diagnosis

- **Enhanced health checks**: Added comprehensive checks for all components
- **DNS diagnosis tool**: Added utility to check cluster-wide DNS resolution
- **Automatic recovery**: Improved restart mechanisms

## Startup Order

For proper deployment, follow this startup sequence:

1. Apply headless service: 
   ```
   kubectl apply -f spark-master-headless.yaml
   ```
2. Deploy StatefulSet for Spark Master:
   ```
   kubectl apply -f spark-master.yaml
   ```
3. Wait for master to become ready:
   ```
   kubectl wait --for=condition=Ready pod/spark-master-0 -n spark --timeout=120s
   ```
4. Deploy workers:
   ```
   kubectl apply -f spark-worker.yaml
   ```
5. Deploy history server:
   ```
   kubectl apply -f spark-history.yaml
   ```

## Testing & Verification

To verify proper DNS resolution:

```bash
# Run DNS diagnosis
kubectl exec -it -n spark spark-master-0 -- ./check-spark-health.sh dns

# Run full health check
kubectl exec -it -n spark spark-master-0 -- ./check-spark-health.sh all
```

## Lab1/Lab2 Deployment Strategy

### Lab2 (Kubernetes Master Node)
- Kubernetes Master components
- Spark Master (StatefulSet)
- Spark History Server
- Infrastructure services

### Lab1 (Worker Node)
- Additional Spark Workers
- User workloads
- iPython

When Lab1 comes online, deploy additional worker pods there using node selectors/affinity to optimize resource usage.
