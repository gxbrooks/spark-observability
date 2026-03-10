# Spark Observability

A comprehensive observability platform for Apache Spark applications running on Kubernetes, integrated with Elasticsearch, Kibana, Grafana, and Logstash.

## 🏗️ Project Organization

### Core Components

```
spark-observability/
├── ansible/                    # Infrastructure automation
│   ├── inventory.yml          # Host definitions
│   ├── playbooks/             # Ansible playbooks
│   │   ├── k8s/               # Kubernetes management
│   │   ├── observability/    # Observability platform
│   │   ├── spark/            # Spark deployment
│   │   └── ea/               # Elastic Agent management
│   └── roles/                # Ansible roles
├── docs/                      # Project documentation
│   ├── PROJECT_OVERVIEW.md   # Comprehensive setup guide
│   ├── Variable_Flow.md      # Variable management architecture
│   └── SECURE_SPARK_DEPLOYMENT.md
├── observability/            # Observability platform
│   ├── docker-compose.yml    # Docker services
│   ├── elasticsearch/        # Elasticsearch configuration
│   ├── kibana/              # Kibana configuration
│   ├── logstash/            # Logstash configuration
│   └── grafana/             # Grafana configuration
├── spark/                    # Spark applications and configuration
│   ├── apps/                # Spark application examples
│   ├── conf/                # Spark configuration
│   └── ispark/              # Interactive Spark development
├── elastic-agent/           # Elastic Agent configuration
├── linux/                   # Linux utilities and scripts
└── vars/variables.yaml           # Central variable definitions
```

### Key Features

- **🔧 Infrastructure as Code**: Complete Ansible automation for Kubernetes, Spark, and observability stack
- **📊 Comprehensive Observability**: Elasticsearch, Kibana, Grafana, and Logstash integration
- **🚀 Spark on Kubernetes**: Production-ready Spark deployment with security
- **📈 Event Monitoring**: Real-time Spark event collection and analysis
- **🔐 Security First**: TLS certificates, secure configurations, and best practices
- **⚙️ Variable Management**: Centralized configuration with context-specific deployment

## 🚀 Quick Start

### Prerequisites
- Ansible installed on control machine
- SSH access to target servers
- Python 3.x

### Basic Setup
```bash
# 1. Deploy infrastructure
cd ansible
ansible-playbook -i inventory.yml playbooks/k8s/install_k8s.yml
ansible-playbook -i inventory.yml playbooks/nfs/install_nfs.yml

# 2. Deploy Spark
ansible-playbook -i inventory.yml playbooks/spark/deploy_spark.yml

# 3. Deploy observability platform
ansible-playbook -i inventory.yml playbooks/observability/install.yml
```

### Run Spark Applications
```bash
# Direct execution (recommended)
python3 spark/apps/Chapter_03.py

# Interactive development
cd spark/ispark && ./launch_ipython.sh
```

## 📚 Documentation

- **[Project Overview](docs/PROJECT_OVERVIEW.md)** - Comprehensive setup and usage guide
- **[Variable Flow](docs/Variable_Flow.md)** - Variable management architecture
- **[Secure Spark Deployment](docs/SECURE_SPARK_DEPLOYMENT.md)** - Security best practices
- **[Running Ansible Playbooks](docs/RUNNING_ANSIBLE_PLAYBOOKS.md)** - Ansible usage guide

## 🏷️ Recent Releases

- **vObservabilityFramework+2**: Consolidated observability playbooks, fixed Python version configuration
- **vObservabilityFramework+1**: Initial observability platform implementation

## 🔗 Service URLs

After deployment, services are accessible at:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Kibana** | http://GaryPC.lan:5601 | elastic / myElastic2025 |
| **Grafana** | http://GaryPC.lan:3000 | admin / (see `vars/contexts/observability_docker.env`) |
| **Elasticsearch** | https://GaryPC.lan:9200 | elastic / myElastic2025 |
| **Spark History** | http://Lab2.lan:31534 | (no auth) |

## 🛠️ Development

### Variable Management
```bash
# Regenerate all environment files (recommended - uses wrapper)
bash vars/generate_contexts.sh -f

# Regenerate specific contexts
bash vars/generate_contexts.sh spark-client elastic-agent

# Or directly (requires PyYAML installed)
python3 vars/generate_contexts.py -f
```

### Running Tests
```bash
# Test Spark event flow
python3 spark/apps/Chapter_03.py

# Check observability platform status
ansible-playbook -i ansible/inventory.yml ansible/playbooks/observability/status.yml
```

## 📋 Architecture

### Spark Event Flow
```
Spark Applications → Event Logs (NFS) → Spark History Server
                                    ↓
Elastic Agent → Logstash → Elasticsearch → Kibana
```

### Variable Flow (Modular Architecture)
```
vars/variables.yaml + vars/contexts.yaml
        ↓
vars/generate_contexts.sh (bootstrap wrapper - uses system Python)
        ↓
vars/generate_contexts.py (core generator)
        ↓
Context-specific files (vars/contexts/*/)
        ↓
Deployment (Ansible/Docker/Kubernetes)
```

**Key Design**: The `vars/` module is **independent** and uses **system Python** to break circular dependencies, allowing environment files to be generated before project dependencies are installed.

## 🤝 Contributing

1. Follow the variable management system in `vars/variables.yaml`
2. Update documentation in `docs/` directory
3. Test changes with Ansible playbooks
4. Ensure security best practices are maintained

## 📄 License

This project is part of a comprehensive observability solution for Apache Spark workloads.