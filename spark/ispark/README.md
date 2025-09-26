# iSpark - Interactive Spark Client

A Python client for connecting to remote Spark clusters from your local development environment.

## Features

- **Local Development**: Run IPython locally with your files and environment
- **Remote Execution**: Submit jobs to remote Spark cluster for processing
- **Easy Setup**: Simple script-based setup and connection
- **Variable Integration**: Uses variables from `variables.yaml` via generated `ispark_env.sh` file

## Usage

```bash
# Make the script executable
chmod +x launch_ipython.sh

# Launch IPython with Spark connection (from any directory)
./launch_ipython.sh

# Or run from anywhere using absolute path
/path/to/spark/ispark/launch_ipython.sh
```

**Note**: The script automatically finds its dependent files (`ispark_env.sh` and `spark_ipython_client.py`) relative to its own location, so it can be launched from any working directory.

## Architecture

```
Your Local Machine          Kubernetes Cluster
┌─────────────────┐         ┌─────────────────┐
│ IPython Client  │ ──────▶│ Spark Master    │
│ (PySpark)       │         │ (Lab2.lan:32582)│
│                 │         │                 │
│ - Local files   │         │ - Spark Workers │
│ - Local env     │         │ - Data processing│
│ - Development   │         │ - Resource mgmt │
└─────────────────┘         └─────────────────┘
```

## Variable Flow

Variables flow from `variables.yaml` → `ispark_env.sh` → `launch_ipython.sh`:

1. **`variables.yaml`**: Contains `SPARK_MASTER_EXTERNAL_HOST` and `SPARK_MASTER_EXTERNAL_PORT` with `ispark` context
2. **`generate_env.py`**: Generates `spark/ispark/ispark_env.sh` from variables.yaml
3. **`launch_ipython.sh`**: Sources `ispark_env.sh` to get variables
4. **`spark_ipython_client.py`**: Uses the variables to connect to Spark cluster

## Files

- **`spark_ipython_client.py`**: Python client that connects to Spark and launches IPython
- **`launch_ipython.sh`**: Shell script that sets up environment and launches the Python client
- **`ispark_env.sh`**: Generated environment file with Spark connection variables
- **`README.md`**: This documentation

## Regenerating Variables

To update the environment variables after changing `variables.yaml`:

```bash
python3 ../../linux/generate_env.py ispark --force
```
