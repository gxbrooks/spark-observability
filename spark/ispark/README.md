# Interactive Spark Client (iPython)

Launch an interactive IPython session with PySpark connected to the Kubernetes Spark cluster.

## Quick Start

```bash
# From anywhere in the project:
./spark/ispark/launch_ipython.sh
```

This launches the standard `pyspark` command with IPython as the driver.

## What It Does

The script:
1. Activates the Python virtual environment
2. Sources Spark environment variables from `ispark_env.sh`
3. Configures `PYSPARK_DRIVER_PYTHON=ipython`
4. Launches `pyspark` connected to the cluster

## Architecture

```
Local Machine                     Kubernetes Cluster (Lab2.lan:31686)
┌─────────────────┐              ┌─────────────────────────────┐
│ IPython Shell   │              │ Spark Master                │
│ (Local)         │ ────────────▶│ spark-master-0              │
│                 │              │                             │
│ SparkSession    │              │ Spark Workers (7 workers)   │
│ spark.read()    │              │ - 5 on Lab1                 │
│ spark.sql()     │              │ - 2 on Lab2                 │
│                 │              │                             │
│ Driver          │              │ Executors                   │
│ (runs locally)  │              │ (run in cluster)            │
└─────────────────┘              └─────────────────────────────┘
```

## Requirements

- Python 3.8 virtual environment with PySpark 3.5.1
- IPython installed in venv
- Spark cluster running on Kubernetes
- Network access to Lab2.lan:31686

## Environment Variables

The `ispark_env.sh` file (auto-generated from `variables.yaml`) provides:
- `SPARK_MASTER_EXTERNAL_HOST`: Cluster hostname (Lab2.lan)
- `SPARK_MASTER_EXTERNAL_PORT`: NodePort for client access (31686)
- Other Spark-related settings

These are automatically sourced by the launch script.

## Usage Example

```bash
$ ./spark/ispark/launch_ipython.sh

=== Launching PySpark with IPython ===
Spark Master: spark://Lab2.lan:31686
Python: /home/user/repos/elastic-on-spark/venv/bin/python
Press Ctrl+D to exit
======================================

Python 3.8.20 (default, ...)
IPython 8.x.x

In [1]: # SparkSession is automatically created as 'spark'

In [2]: spark
Out[2]: <pyspark.sql.session.SparkSession at 0x...>

In [3]: df = spark.read.csv("/mnt/spark/data/sample.csv")

In [4]: df.show()
+---+------+
| id| value|
+---+------+
|  1|   foo|
|  2|   bar|
+---+------+
```

## Alternative: Direct PySpark Command

If you've sourced the environment (via `linux/.bashrc`), you can also run:

```bash
source venv/bin/activate
pyspark
```

The environment variables are already configured, so it connects to the cluster automatically.

## Regenerating Environment

If cluster configuration changes, regenerate environment files:

```bash
python3 linux/generate_env.py ispark
```

This updates `ispark_env.sh` with the latest values from `variables.yaml`.
