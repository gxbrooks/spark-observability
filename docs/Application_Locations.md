# Application Locations and Installation Guide

This document provides a comprehensive overview of where applications are installed and how to access them in the elastic-on-spark project.

## **Development Environment Setup**

### **Python Environment**
- **Location**: `/home/gxbrooks/repos/elastic-on-spark/venv/`
- **Python Version**: 3.11 (required for Apache Spark 4.0+)
- **Activation**: `source venv/bin/activate`
- **Deactivation**: `deactivate`
- **Note**: Python version is defined in `vars/variables.yaml` and is the single source of truth

### **PySpark Installation**
- **Location**: Virtual environment (`venv/lib/python3.11/site-packages/`)
- **Version**: 4.0.1 (matches Spark cluster version)
- **Installation Method**: Virtual environment (no system pollution)
- **Access**: Available when virtual environment is activated

## **Application Locations Table**

| Application | Location | Purpose | Access Method |
|-------------|----------|---------|---------------|
| **Python 3.11** | `/usr/bin/python3.11` or `/usr/local/bin/python3.11` | System Python | `python3.11` or `python3` |
| **PySpark** | `venv/lib/python3.11/site-packages/` | Spark Python API | `source venv/bin/activate` then `python` |
| **IPython** | `venv/bin/ipython` | Interactive Spark (client-mode) | `source venv/bin/activate` then `ipython` |
| **Spark Master UI** | `http://Lab2.lan:32290` | Spark cluster monitoring | Web browser |
| **Spark History Server** | `http://Lab2.lan:31534` | Historical job analysis | Web browser |
| **HDFS Client** | `/usr/bin/hdfs` | Hadoop HDFS CLI | `hdfs` (via wrapper) |
| **Spark Submit** | `venv/bin/spark-submit` | Spark job submission | `source venv/bin/activate` then `spark-submit` |
| **Git** | `/usr/bin/git` | Version control | `git` |
| **Ansible** | `/usr/bin/ansible` | Infrastructure automation | `ansible` |
| **Kubectl** | `/usr/bin/kubectl` | Kubernetes CLI | `kubectl` |

> **Note:** JupyterHub will be added during Spark 4.0 migration with Python 3.11 support.

## **Environment Configuration**

### **Bash Environment**
- **Configuration File**: `linux/.bashrc`
- **User Integration**: `linux/link_to_user_env.sh`
- **Virtual Environment PATH**: Automatically added to PATH when sourced

### **SSH Configuration**
- **SSH Keys**: `~/.ssh/`
- **SSH Agent**: Managed by `linux/.bashrc`
- **Git Integration**: Configured in `initialize_devops_client.sh`

## **Development Workflow**

### **1. Initial Setup**
```bash
# Run the main initialization script
./linux/initialize_devops_client.sh -N "your-passphrase"
```

### **2. Daily Development**
```bash
# Activate virtual environment
source venv/bin/activate

# Run Spark applications
python spark/apps/Chapter_XX.py

# Use interactive Python
ipython

# Use Jupyter Notebook
jupyter notebook
```

### **3. HDFS Operations**
```bash
# List HDFS contents
hdfs dfs -ls /

# Copy files to HDFS
hdfs dfs -put local_file.txt /spark/
```

## **Key Scripts and Their Purposes**

| Script | Purpose | Usage |
|--------|---------|-------|
| `initialize_devops_client.sh` | Main setup script | `./linux/initialize_devops_client.sh -N "passphrase"` |
| `assert_python_version.sh` | Python installation | `./linux/assert_python_version.sh --PythonVersion 3.11 --SetupVenv` |
| `link_to_user_env.sh` | Environment integration | `./linux/link_to_user_env.sh` |
| `hdfs-wrapper.sh` | HDFS client wrapper | `hdfs` (automatic via alias) |
| `spark-python-wrapper.sh` | Python version wrapper (legacy) | Not recommended - use devops_env.sh instead |

## **Best Practices**

### **✅ Recommended**
- Use virtual environment for all Python development
- Activate venv before running Spark applications
- Use wrapper scripts for version compatibility
- Keep system Python clean

### **❌ Avoid**
- Installing Python packages globally with `--user` or `--break-system-packages`
- Mixing system and virtual environment Python packages
- Running Spark applications without activating virtual environment

## **Troubleshooting**

### **Common Issues**
1. **Python Version Mismatch**: Ensure virtual environment is activated
2. **PySpark Not Found**: Check if venv is activated and PySpark is installed
3. **HDFS Connection Issues**: Verify Hadoop cluster is running and accessible
4. **Permission Issues**: Check file ownership and NFS mount permissions

### **Verification Commands**
```bash
# Check Python version
python --version

# Check PySpark installation
python -c "import pyspark; print(pyspark.__version__)"

# Check virtual environment
which python

# Check HDFS connectivity
hdfs dfs -ls /
```

## **File Structure**
```
elastic-on-spark/
├── venv/                          # Virtual environment (Python 3.11)
│   ├── bin/                      # Executables (python, pip, etc.)
│   ├── lib/python3.11/site-packages/  # Python packages
│   └── pyvenv.cfg               # Virtual environment config
├── linux/                        # Linux-specific scripts
│   ├── .bashrc                  # Environment configuration
│   ├── .bash_aliases            # Command aliases
│   ├── assert_python_version.sh # Python installation
│   ├── hdfs-wrapper.sh          # HDFS client wrapper
│   └── spark-python-wrapper.sh  # Python version wrapper
├── spark/                        # Spark applications
│   └── apps/                    # Chapter files
└── .gitignore                   # Git ignore rules
```
