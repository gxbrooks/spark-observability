# Spark Directory - DEPRECATED DOCKER APPROACH

## ⚠️ DEPRECATION NOTICE

**This directory contains deprecated Docker-based Spark image building components.**

### Deprecated Files:
- `Dockerfile` - Custom Spark image building (DEPRECATED)
- `spark-image.toml` - Build-time variables (DEPRECATED) 
- `entrypoint.sh` - Custom entrypoint script (DEPRECATED)
- `check-spark-health.sh` - Custom health checks (DEPRECATED)
- `k8s-readiness.sh` - Custom readiness checks (DEPRECATED)

### Current Approach:
- **Standard Apache Spark Image**: Uses `docker.io/apache/spark:3.5.1`
- **Runtime Configuration**: All variables provided via Kubernetes ConfigMap
- **Centralized Variables**: Managed through `variables.yaml` and `generate_env.py`
- **Standard Scripts**: Uses built-in Spark scripts (`start-master.sh`, `start-worker.sh`, etc.)

### Migration:
All Spark configuration is now handled at runtime through:
1. **`variables.yaml`** - Single source of truth for all variables
2. **`generate_env.py`** - Generates `spark-configmap.yaml` with runtime variables
3. **Kubernetes ConfigMap** - Provides environment variables to standard Spark image

### Why Deprecated:
- **Simpler**: No custom image building required
- **Maintainable**: Uses standard Apache Spark image
- **Flexible**: Runtime configuration via environment variables
- **Consistent**: Same variable system across all components (Spark, K8s, Observability)

---

**Note**: The `images/` directory still contains the Spark archive for potential future use, but the Docker-based image building approach is no longer recommended.

