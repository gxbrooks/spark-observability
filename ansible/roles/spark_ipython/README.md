# Spark IPython Role

This role provides functionality to launch an IPython environment integrated with PySpark in a Kubernetes pod. This enables interactive development and debugging of Spark applications.

## Prerequisites

- A running Kubernetes cluster with Spark deployed using the `deploy_spark.yml` playbook
- The `kubectl` command-line tool installed and properly configured
- Access to the Spark Docker image (typically in a local registry)

## Role Variables

| Variable | Description | Default Value |
|----------|-------------|---------------|
| `pyspark_ipython_pod_name` | Name of the pod that will run IPython | `pyspark-ipython` |
| `pyspark_ipython_cpu_request` | CPU request for the pod | `500m` |
| `pyspark_ipython_memory_request` | Memory request for the pod | `1Gi` |
| `pyspark_ipython_cpu_limit` | CPU limit for the pod | `1` |
| `pyspark_ipython_memory_limit` | Memory limit for the pod | `2Gi` |
| `launch_shell` | Whether to launch an interactive shell | `true` |

## Example Usage

```yaml
- hosts: localhost
  roles:
    - role: spark_ipython
      pyspark_ipython_memory_limit: "4Gi"
      pyspark_ipython_cpu_limit: "2"
```

## Interactive Mode

When `launch_shell` is set to `true` (default), the playbook will:
1. Create a PySpark IPython pod
2. Launch an interactive IPython shell connected to the pod
3. When the user exits IPython, the pod remains and needs to be cleaned up manually

## Non-interactive Mode

When `launch_shell` is set to `false`, the playbook will:
1. Create a PySpark IPython pod without connecting to it
2. Leave the pod running for later connections

This mode is useful for setting up development environments that users can connect to later.
