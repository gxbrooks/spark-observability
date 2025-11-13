# Spark Applications

This directory contains Apache Spark applications and client tools for running workloads on the Kubernetes-based Spark cluster.

## Quick Start

### Prerequisites

1. **Virtual Environment**: Python 3.8 with PySpark 3.5.1
   ```bash
   # Create and activate venv (first time)
   python3.8 -m venv venv
   source venv/bin/activate
   pip install pyspark==3.5.1 ipython
   ```

2. **Spark Cluster**: Running on Kubernetes (Lab2.local)
   ```bash
   # Start cluster if needed
   cd ansible && ansible-playbook -i inventory.yml playbooks/start.yml
   ```

3. **Configuration**: Environment variables generated from `variables.yaml`
   ```bash
   # Regenerate if needed
   python3 linux/generate_env.py spark-client ispark
   ```

## Running Spark Applications

### Batch Mode (Python Scripts)

Execute Spark applications as standard Python scripts:

```bash
# Activate virtual environment
source venv/bin/activate

# Run a Spark application
python spark/apps/Chapter_03.py
python spark/apps/Chapter_04.py

# Deactivate when done
deactivate
```

**How It Works:**
- Driver runs **locally** on your machine
- Executors run **remotely** in Kubernetes cluster
- Connects to Spark master at `spark://Lab2.local:31686`
- Event logs written to `/mnt/spark/events` (NFS mount)

### Interactive Mode (IPython)

Launch an interactive IPython session with PySpark using the standard `pyspark` command:

```bash
# Activate virtual environment
source venv/bin/activate

# Option 1: Use the launch script (recommended)
./spark/ispark/launch_ipython.sh

# Option 2: Direct pyspark command (if environment sourced)
pyspark
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

**Note:** The environment is configured in `linux/.bashrc` to automatically use IPython for PySpark interactive sessions (`PYSPARK_DRIVER_PYTHON=ipython`).

## Directory Structure

```
spark/
├── apps/                    # Batch Spark applications
│   ├── Chapter_03.py        # Example: Basic DataFrame operations
│   ├── Chapter_04.py        # Example: SQL and transformations
│   ├── chapter*/            # Additional examples by chapter
│   └── ...                  # More applications
├── conf/                    # Client configuration
│   ├── spark-defaults.conf  # Spark properties for client apps
│   ├── log4j2.properties    # Logging configuration
│   └── log4j2-executor.properties  # Executor logging
├── ispark/                  # Interactive Spark client
│   ├── launch_ipython.sh    # Launch script for iPython
│   ├── ispark_env.sh        # Generated environment variables
│   └── README.md            # Interactive mode documentation
├── requirements/            # Python dependencies
│   ├── requirements.in      # Source dependencies
│   └── requirements.txt     # Generated requirements
├── spark_env.sh             # Generated environment (for batch)
└── README.md                # This file
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
Auto-generated from `variables.yaml`:
- `spark_env.sh`: Environment variables for batch apps
- `ispark/ispark_env.sh`: Environment variables for interactive mode

## Connectivity

### Spark Cluster Access

**Master Service:**
- Internal (cluster): `spark://spark-master-0.spark-master-headless.spark.svc.cluster.local:7077`
- External (clients): `spark://Lab2.local:31686`

**Web UIs:**
- Spark Master UI: http://Lab2.local:32636
- Spark History Server: http://Lab2.local:31534

### Network Requirements

Client applications need:
- Network access to Lab2.local on ports 31686 (Spark), 32636 (UI)
- NFS mount at `/mnt/spark/events` for event logging
- NFS mount at `/mnt/spark/data` for data access (if needed)

## Troubleshooting

### Common Issues

**"Connection refused" when running apps:**
- Check cluster is running: `kubectl get pods -n spark`
- Start cluster: `cd ansible && ansible-playbook -i inventory.yml playbooks/start.yml`
- Verify port: `nc -zv Lab2.local 31686`

**"PySpark not found":**
- Activate virtual environment: `source venv/bin/activate`
- Install PySpark: `pip install pyspark==3.5.1`

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

The `apps/` directory contains example Spark applications from "Spark in Action":

- **Chapter_03.py**: DataFrame basics
- **Chapter_04.py**: SQL queries and transformations
- **Chapter_05.py**: Data aggregations
- **Chapter_06.py**: Joins and data enrichment
- **Chapter_07.py**: Advanced operations
- ...and more

Each can be run independently as shown in the "Batch Mode" section above.

## Notes

- **Architecture**: Client-mode deployment (driver local, executors in K8s)
- **Logs**: Driver logs to console, executor logs to cluster
- **Data Access**: Via NFS mounts or HDFS (if configured)
- **Monitoring**: Full observability via Elasticsearch, Kibana, Grafana
