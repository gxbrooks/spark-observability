# Spark Applications

This directory contains Apache Spark applications and client tools for running workloads on the Kubernetes-based Spark cluster.

## Quick Start

### Prerequisites

1. **Virtual Environment**: Python 3.11 with PySpark 4.0.1
   ```bash
   # Create and activate venv (first time)
   python3.11 -m venv venv
   source venv/bin/activate
   pip install pyspark==4.0.1 ipython
   ```

2. **Spark Cluster**: Running on Kubernetes (Lab2.lan)
   ```bash
   # Start cluster if needed
   cd ansible && ansible-playbook -i inventory.yml playbooks/start.yml
   ```

3. **Configuration**: Environment variables generated from `vars/variables.yaml`
   ```bash
   # Regenerate if needed (use wrapper script - recommended)
   bash vars/generate_env.sh devops spark-client ispark
   
   # Or directly (requires PyYAML installed)
   python3 vars/generate_env.py devops spark-client ispark
   ```

## Running Spark Applications

Spark applications can be run in three modes:

1. **Client Mode** - Driver runs locally, executors in cluster (recommended for development)
2. **iSpark Mode** - Interactive IPython session with Spark (for exploration)
3. **Cluster Mode** - Driver and executors run in cluster (for production)

### Mode 1: Client Mode (via Environment Variables)

Execute Spark applications as standard Python scripts with the driver running locally.

#### Precursor Steps

The `.bashrc` file automatically sets up the environment on login. For manual setup:

```bash
# 1. Source devops environment (Python version, OTel config, etc.)
source vars/contexts/devops/devops_env.sh

# 2. Set SPARK_LOCAL_IP to suppress hostname resolution warnings
export SPARK_LOCAL_IP="${SPARK_LOCAL_IP:-192.168.1.48}"

# 3. Generate spark-defaults.conf from template
./linux/generate_spark_defaults.sh

# 4. Source Spark client environment variables
source vars/contexts/spark-client/spark_env.sh
export SPARK_MASTER_URL="spark://${SPARK_MASTER_HOST}:${SPARK_MASTER_PORT}"

# 5. Configure PySpark to use IPython for interactive sessions (optional)
export PYSPARK_DRIVER_PYTHON=ipython
export PYSPARK_DRIVER_PYTHON_OPTS=""
```

#### Running Applications

```bash
# Activate virtual environment
source venv/bin/activate

# Run a Spark application
python spark/apps/data-analysis-book/Chapter_03.py
python spark/apps/data-analysis-book/Chapter_07.py

# Deactivate when done
deactivate
```

**How It Works:**
- Driver runs **locally** on your machine
- Executors run **remotely** in Kubernetes cluster
- Connects to Spark master at `spark://Lab2.lan:31686`
- Event logs written to `/mnt/spark/events` (NFS mount)
- Configuration from `spark/conf/spark-defaults.conf`

### Mode 2: iSpark Mode (Interactive IPython)

Launch an interactive IPython session with PySpark for exploratory data analysis.

#### Precursor Steps

The `launch_ipython.sh` script handles setup automatically. Manual steps:

```bash
# 1. Source iSpark environment variables
source vars/contexts/ispark/ispark_env.sh
export SPARK_MASTER_URL="spark://${SPARK_MASTER_HOST}:${SPARK_MASTER_PORT}"

# 2. Activate virtual environment
source venv/bin/activate

# 3. Configure PySpark to use IPython
export PYSPARK_DRIVER_PYTHON=ipython
export PYSPARK_DRIVER_PYTHON_OPTS=""
```

#### Running iSpark

```bash
# Option 1: Use the launch script (recommended)
./spark/ispark/launch_ipython.sh

# Option 2: Direct pyspark command (if environment sourced)
pyspark --master ${SPARK_MASTER_URL}
```

**Inside IPython:**
```python
# SparkSession is automatically available as 'spark'
>>> spark
<pyspark.sql.session.SparkSession at 0x...>

# Use Spark interactively
>>> df = spark.read.csv("/mnt/spark/data/sample.csv")
>>> df.show()
```

**To Exit:** Press `Ctrl+D` or type `exit()`

**How It Works:**
- IPython shell runs **locally**
- SparkSession driver runs **locally**
- Executors run **remotely** in Kubernetes cluster
- Same connection and configuration as Client Mode

### Mode 3: Cluster Mode (via spark-submit)

Submit Spark applications to run entirely in the Kubernetes cluster.

#### Precursor Steps

```bash
# 1. Source devops environment for Python version and OTel config
source vars/contexts/devops/devops_env.sh

# 2. Ensure virtual environment is activated (for Python dependencies)
source venv/bin/activate

# 3. Set SPARK_HOME if using local Spark installation
export SPARK_HOME="${SPARK_HOME:-/opt/spark}"
```

#### Running Applications

```bash
# Using spark-submit from Kubernetes pod (recommended)
kubectl exec -n spark spark-master-0 -c spark-master -- \
  /opt/spark/bin/spark-submit \
  --master spark://spark-master-0.spark-master-headless.spark.svc.cluster.lan:7077 \
  --deploy-mode cluster \
  --conf spark.kubernetes.container.image=spark:4.0.1 \
  --conf spark.kubernetes.namespace=spark \
  --py-files /path/to/dependencies.zip \
  /path/to/application.py

# Or using local spark-submit (if Spark installed locally)
spark-submit \
  --master k8s://https://Lab2.lan:6443 \
  --deploy-mode cluster \
  --conf spark.kubernetes.container.image=spark:4.0.1 \
  --conf spark.kubernetes.namespace=spark \
  spark/apps/data-analysis-book/Chapter_07.py
```

**How It Works:**
- Driver runs **in Kubernetes cluster** (as a pod)
- Executors run **in Kubernetes cluster** (as pods)
- No local driver process
- Better resource isolation and scaling
- Requires Kubernetes access and proper image configuration

## Directory Structure

```
spark/
├── apps/                              # Batch Spark applications
│   ├── data-analysis-book/            # Example applications by chapter
│   │   ├── Chapter_03.py              # Basic DataFrame operations
│   │   ├── Chapter_04.py              # SQL and transformations
│   │   ├── Chapter_05.py              # Data aggregations
│   │   ├── Chapter_06.py              # Joins and data enrichment
│   │   ├── Chapter_07.py              # Advanced operations
│   │   └── ...                        # More chapters
│   ├── gsod/                          # GSOD data processing examples
│   └── spark-warehouse/               # Spark SQL warehouse directory
├── conf/                              # Client configuration
│   ├── spark-defaults.conf            # Generated Spark properties (from .j2 template)
│   ├── spark-defaults.conf.j2         # Jinja2 template for Spark config
│   ├── log4j2.properties              # Logging configuration
│   ├── log4j2-client.properties       # Client-specific logging
│   └── log4j2-cluster.properties      # Cluster-specific logging
├── ispark/                            # Interactive Spark client
│   ├── launch_ipython.sh              # Launch script for iPython
│   └── README.md                      # Interactive mode documentation
├── otel-listener/                     # OpenTelemetry listener for Spark
│   ├── src/                           # Scala source code
│   ├── pom.xml                        # Maven build configuration
│   ├── spark-otel-listener-1.0.0.jar  # Compiled JAR
│   └── README.md                      # OTel listener documentation
├── images/                            # Spark distribution archives
│   ├── spark-3.5.1-bin-hadoop3.tgz
│   └── spark-4.0.1-bin-hadoop3.tgz
├── requirements/                      # Python dependencies
│   ├── requirements.in                # Source dependencies
│   └── requirements.txt               # Generated requirements
├── run_with_otel.sh                   # Helper script for OTel-enabled runs
└── README.md                          # This file
```

**Note:** This directory only contains client-side code. The Spark cluster runs on Kubernetes using the standard Apache Spark image.

## Configuration Files

### `conf/spark-defaults.conf`
Client-mode Spark configuration:
- `spark.master`: Connection to Kubernetes cluster
- `spark.eventLog.dir`: Event log directory
- JVM options for GC logging
- Network timeouts and settings

### Generated Environment Files
Auto-generated from `vars/variables.yaml` via `vars/generate_env.py`:
- `vars/contexts/devops/devops_env.sh`: DevOps environment (Python version, OTel config)
- `vars/contexts/spark-client/spark_env.sh`: Client mode environment variables
- `vars/contexts/ispark/ispark_env.sh`: Interactive mode environment variables

## Connectivity

### Spark Cluster Access

**Master Service:**
- Internal (cluster): `spark://spark-master-0.spark-master-headless.spark.svc.cluster.lan:7077`
- External (clients): `spark://Lab2.lan:31686`

**Web UIs:**
- Spark Master UI: http://Lab2.lan:32636
- Spark History Server: http://Lab2.lan:31534

### Network Requirements

Client applications need:
- Network access to Lab2.lan on ports 31686 (Spark), 32636 (UI)
- NFS mount at `/mnt/spark/events` for event logging
- NFS mount at `/mnt/spark/data` for data access (if needed)

## Troubleshooting

### Common Issues

**"Connection refused" when running apps:**
- Check cluster is running: `kubectl get pods -n spark`
- Start cluster: `cd ansible && ansible-playbook -i inventory.yml playbooks/start.yml`
- Verify port: `nc -zv Lab2.lan 31686`

**"PySpark not found":**
- Activate virtual environment: `source venv/bin/activate`
- Install PySpark: `pip install pyspark==4.0.1`

**"Version mismatch" or "InvalidClassException":**
- Ensure local PySpark version matches cluster Spark version (4.0.1)
- Check cluster version: `kubectl exec -n spark spark-master-0 -c spark-master -- /opt/spark/bin/spark-submit --version`
- Reinstall matching version: `pip install pyspark==4.0.1`

**"Java not found":**
- Install Java: `sudo apt install openjdk-11-jdk`
- Set JAVA_HOME: `export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64`

**Event logs not appearing:**
- Check NFS mount: `ls -la /mnt/spark/events`
- Mount NFS: See NFS installation playbooks

### Verification Script

Use the assertion script to verify your environment:

```bash
# Check current configuration
./linux/assert_spark_client_apps.sh --Check

# Automatically fix issues
./linux/assert_spark_client_apps.sh --Fix

# Debug mode for troubleshooting
./linux/assert_spark_client_apps.sh --Debug
```

## Best Practices

### For Development

1. **Always use virtual environment** for dependency isolation
2. **Test locally first** with small datasets
3. **Monitor cluster resources** - check Spark UI
4. **Review event logs** in History Server after jobs complete

### For Production

1. **Pin dependency versions** in requirements.txt
2. **Configure appropriate memory** in spark-defaults.conf
3. **Enable event logging** for debugging (already configured)
4. **Monitor GC logs** via Elastic Agent and Kibana

## Example Applications

The `apps/data-analysis-book/` directory contains example Spark applications:

- **Chapter_03.py**: DataFrame basics and word count analysis
- **Chapter_04.py**: SQL queries and transformations
- **Chapter_05.py**: Data aggregations
- **Chapter_06.py**: Joins and data enrichment
- **Chapter_07.py**: Advanced operations and data aggregation
- **Chapter_08.py**: Window functions and advanced SQL
- **Chapter_09.py**: Additional examples
- **Chapter_10.py**: Additional examples

Each can be run independently in Client Mode or Cluster Mode as shown above.

## Notes

- **Architecture**: Supports client-mode (driver local) and cluster-mode (driver in K8s)
- **Python Version**: Python 3.11 with PySpark 4.0.1 (must match cluster Spark version)
- **Logs**: Driver logs to console (client mode) or cluster (cluster mode), executor logs to cluster
- **Data Access**: Via NFS mounts or HDFS (if configured)
- **Monitoring**: Full observability via Elasticsearch, Kibana, Grafana
- **OpenTelemetry**: Traces automatically sent to Otel collector when OTel listener is configured
- **Environment**: Always use virtual environment (`venv`) and source appropriate context files
