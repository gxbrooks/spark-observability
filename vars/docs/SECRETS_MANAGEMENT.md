# Secrets Management

## Overview

This document describes how secrets (passwords, encryption keys, etc.) are managed in the Elastic-on-Spark project. The system uses a **multi-layered approach** with priority-based resolution to ensure security while maintaining flexibility.

## Security Principles

1. **Never commit secrets to version control** - All secrets are stored in `vars/secrets.yaml`, which is gitignored
2. **No default passwords** - All required secrets must be explicitly set (no defaults in code)
3. **Support multiple secret sources** - Environment variables or secrets file
4. **Clear priority order** - Environment variables > secrets.yaml (no fallback to defaults)
5. **Fail fast** - System will not generate configuration files if required secrets are missing
6. **Documentation** - All secrets are clearly marked in `variables.yaml` with `required: true`

## Secret Resolution Priority

When generating context files, secrets are resolved in the following order (highest to lowest priority):

1. **Environment Variables** (highest priority)
   - Example: `export ES_PASSWORD="my-secret-password"`
   - Useful for CI/CD pipelines, Docker containers, or temporary overrides

2. **secrets.yaml file**
   - Located at: `vars/secrets.yaml`
   - Gitignored and never committed
   - Recommended for local development

3. **Required Validation**
   - All secrets marked with `required: true` in `variables.yaml` MUST be provided
   - System will fail with clear error messages if required secrets are missing
   - No default passwords are stored in the codebase

## Setup Instructions

### Initial Setup

**IMPORTANT:** Required secrets must be set before generating context files. The system will fail if required secrets are missing.

1. **Copy the secrets template:**
   ```bash
   cp vars/secrets.yaml.example vars/secrets.yaml
   ```

2. **Edit secrets.yaml with your actual values:**
   ```bash
   # Use your preferred editor
   nano vars/secrets.yaml
   # or
   vim vars/secrets.yaml
   ```
   
   **Required secrets:**
   - `ES_PASSWORD` - Elasticsearch password
   - `KB_PASSWORD` - Kibana system password
   - `GF_SECURITY_ADMIN_PASSWORD` - Grafana admin password
   - `EB_ENCRYPTION_KEY` - Kibana encryption key (must be 32+ characters)

3. **Set secure file permissions:**
   ```bash
   chmod 600 vars/secrets.yaml
   ```

4. **Verify secrets.yaml is gitignored:**
   ```bash
   git status vars/secrets.yaml
   # Should show: "nothing to commit" or file should not appear
   ```

5. **Test that secrets are loaded:**
   ```bash
   bash vars/generate_contexts.sh devops
   # Should succeed without errors
   ```

### Using Environment Variables

For CI/CD pipelines or containerized deployments, you can use environment variables:

```bash
# Set secrets as environment variables
export ES_PASSWORD="production-password"
export KB_PASSWORD="kibana-password"
export GF_SECURITY_ADMIN_PASSWORD="grafana-password"
export EB_ENCRYPTION_KEY="encryption-key"

# Generate context files (will use env vars)
bash vars/generate_contexts.sh
```

## Current Secrets

The following variables are treated as secrets:

| Variable | Description | Default Value | Override Location |
|----------|-------------|---------------|-------------------|
| `ES_PASSWORD` | Elasticsearch password | `myElastic2025` | `vars/secrets.yaml` or `ES_PASSWORD` env var |
| `KB_PASSWORD` | Kibana system password | `myElastic2025` | `vars/secrets.yaml` or `KB_PASSWORD` env var |
| `GF_SECURITY_ADMIN_PASSWORD` | Grafana admin password | `mysecretpassword` | `vars/secrets.yaml` or `GF_SECURITY_ADMIN_PASSWORD` env var |
| `EB_ENCRYPTION_KEY` | Kibana encryption key | (see variables.yaml) | `vars/secrets.yaml` or `EB_ENCRYPTION_KEY` env var |

## Implementation Details

### How It Works

1. **generate_contexts.py** loads secrets from `vars/secrets.yaml` (if it exists)
2. When processing variables, it checks if a variable is marked as `secret: true`
3. For secret variables, it checks in order:
   - Environment variable (via `os.environ.get()`)
   - secrets.yaml dictionary
   - variables.yaml default value
4. The resolved value is used in generated context files

### Code Flow

```python
# In generate_contexts.py
secrets = load_secrets()  # Load from vars/secrets.yaml

# In get_vars()
if var_name in secret_vars:
    secret_value = get_secret_value(var_name, secrets)
    if secret_value:
        expanded_value = secret_value  # Override with secret
```

## Best Practices

### Development Environment

1. Use `vars/secrets.yaml` for local development
2. Keep file permissions restricted: `chmod 600 vars/secrets.yaml`
3. Never commit `vars/secrets.yaml` to git
4. Use different passwords for development vs. production

### Production Environment

1. **Option A: Environment Variables** (Recommended for containers)
   - Set secrets as environment variables in your deployment system
   - Kubernetes: Use Secrets resources
   - Docker Compose: Use `.env` file (gitignored) or environment variables

2. **Option B: External Secret Management** (Recommended for enterprise)
   - HashiCorp Vault
   - AWS Secrets Manager
   - Azure Key Vault
   - Kubernetes Secrets API
   - Integrate with `generate_contexts.py` to fetch secrets

3. **Option C: Ansible Vault** (For Ansible-specific secrets)
   - Use `ansible-vault encrypt_string` for Ansible playbook secrets
   - Separate from variable generation system

### Security Checklist

- [ ] `vars/secrets.yaml` is in `.gitignore`
- [ ] `vars/secrets.yaml` has permissions `600` (owner read/write only)
- [ ] Default passwords in `variables.yaml` are changed in production
- [ ] Secrets are rotated regularly
- [ ] Different secrets used for dev/staging/production
- [ ] Secrets are not logged or printed in scripts
- [ ] CI/CD pipelines use secure secret injection

## Troubleshooting

### Warning: secrets.yaml not found

If you see this warning when running `generate_contexts.sh`:
```
⚠ Warning: secrets.yaml not found. Using default values from variables.yaml
```

**Solution:** Copy the template and create your secrets file:
```bash
cp vars/secrets.yaml.example vars/secrets.yaml
chmod 600 vars/secrets.yaml
# Edit vars/secrets.yaml with your values
```

### Secrets not being used

1. **Check file exists:** `ls -la vars/secrets.yaml`
2. **Check file permissions:** Should be `600` (rw-------)
3. **Check environment variables:** `echo $ES_PASSWORD` (env vars take priority)
4. **Verify variable name:** Must match exactly (case-sensitive)

### Secrets appearing in generated files

If secrets appear in generated context files, this is expected behavior. The generated files are:
- Gitignored (`vars/contexts/` is in `.gitignore`)
- Used only on the target system
- Should have appropriate permissions set by deployment scripts

**Note:** For Kubernetes ConfigMaps, consider using Kubernetes Secrets instead of ConfigMaps for sensitive data.

## Open Source Vault Recommendations

For standalone Linux deployments, here are recommended open source vault solutions:

### 1. HashiCorp Vault (Recommended for Production)

**Best for:** Production deployments requiring advanced features

**Features:**
- REST API for programmatic access
- Dynamic secrets generation
- Audit logging
- Multiple storage backends (file, Consul, etc.)
- Token-based authentication
- Can run standalone with file storage

**Quick Start:**
```bash
# Download Vault
wget https://releases.hashicorp.com/vault/1.15.0/vault_1.15.0_linux_amd64.zip
unzip vault_1.15.0_linux_amd64.zip
sudo mv vault /usr/local/bin/

# Initialize with file storage (standalone)
vault server -config=vault.hcl
```

**Integration:** Update `generate_contexts.py` to fetch secrets via Vault API:
```python
import hvac  # HashiCorp Vault Python client
client = hvac.Client(url='http://localhost:8200')
secret = client.secrets.kv.v2.read_secret_version(path='elastic-on-spark')
```

### 2. SOPS (Mozilla Secrets OPerationS)

**Best for:** Infrastructure-as-code, encrypting files in git

**Features:**
- Encrypts YAML/JSON files directly
- Git-friendly (encrypted files can be committed)
- Simple CLI interface
- Supports multiple encryption backends (GPG, AWS KMS, etc.)

**Quick Start:**
```bash
# Install SOPS
wget https://github.com/getsops/sops/releases/download/v3.8.0/sops-v3.8.0.linux
chmod +x sops-v3.8.0.linux
sudo mv sops-v3.8.0.linux /usr/local/bin/sops

# Encrypt secrets.yaml
sops -e -i vars/secrets.yaml

# Edit encrypted file
sops vars/secrets.yaml
```

**Integration:** Modify `generate_contexts.py` to decrypt with SOPS before loading.

### 3. Pass (Password Store)

**Best for:** Personal/small team use, GPG-based workflows

**Features:**
- Simple GPG-based password manager
- CLI-friendly
- Git-friendly
- Minimal setup

**Quick Start:**
```bash
sudo apt install pass
pass init "your-gpg-key-id"
pass insert elastic-on-spark/ES_PASSWORD
pass elastic-on-spark/ES_PASSWORD  # Retrieve
```

### 4. Ansible Vault

**Best for:** Ansible-heavy workflows

**Features:**
- Integrated with Ansible playbooks
- Encrypts YAML variables
- No additional infrastructure needed

**Quick Start:**
```bash
ansible-vault encrypt_string 'mySecretPassword' --name 'ES_PASSWORD'
```

## Future Enhancements

Potential improvements to the secrets management system:

1. **HashiCorp Vault Integration**
   - Add `hvac` Python client support
   - Fetch secrets via Vault API
   - Support token and AppRole authentication

2. **SOPS Integration**
   - Automatic decryption of encrypted `secrets.yaml`
   - Support for GPG and cloud KMS backends

3. **Secret Rotation**
   - Automated secret rotation
   - Version management for secrets

4. **Audit Logging**
   - Log when secrets are accessed
   - Track secret usage

5. **Secret Validation**
   - Validate secret strength
   - Check for common weak passwords
   - Validate Kibana encryption key length (32+ chars)

## Related Documentation

- [Variable Context Framework Architecture](../ARCHITECTURE.md)
- [Variable Context Framework Implementation](../IMPLEMENTATION.md)
- [Variable Contexts Best Practices](../Variable_Contexts_Best_Practices.md)

