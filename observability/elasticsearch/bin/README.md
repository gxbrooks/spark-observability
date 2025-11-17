# Elasticsearch and Kibana API Scripts

This directory contains unified scripts for making REST API calls to Elasticsearch and Kibana services.

## Files

- **`elastic_api.py`**: Unified Python script for making API calls to both Elasticsearch and Kibana
- **`esapi`**: Shell wrapper for Elasticsearch API calls
- **`kapi`**: Shell wrapper for Kibana API calls

## Architecture

The scripts have been consolidated from the previous `observability/shared/bin/` structure:
- Previously had separate `esapi.py` and `kapi.py` Python modules, plus separate `args.py` and `api.py` modules
- Now consolidated into a single `elastic_api.py` with all functionality
- Simplified shell wrappers that call the unified Python script
- No Docker detection - designed to work in both container and client modes

## Usage

### In Docker Containers

The scripts are automatically available in the `init-index` container via the volume mount:
```yaml
volumes:
  - ./elasticsearch:/usr/share/elasticsearch/elasticsearch
```

The init scripts add the bin directory to PATH automatically.

### In Client Mode

For client mode usage (outside Docker containers):

1. **Python 3 with requests module**:
   
   The `requests` module is automatically installed when you run `linux/assert_devops_client.sh`, which sets up the project venv with all required dependencies including `requests`, `pyyaml`, and `toml`.
   
   To manually install if needed:
   ```bash
   pip install requests
   ```

2. **Required environment variables** (automatically set when you source `vars/contexts/devops/devops_env.sh`):
   - `CA_CERT`: Path to CA certificate
   - `ELASTIC_HOST_CLIENT` or `ELASTIC_HOST`: Elasticsearch hostname
   - `ELASTIC_PORT`: Elasticsearch port
   - `ELASTIC_USER`: Username
   - `ELASTIC_PASSWORD`: Password
   - `KIBANA_HOST_CLIENT` or `KIBANA_HOST`: Kibana hostname
   - `KIBANA_PORT`: Kibana port
   - `KIBANA_PASSWORD`: Kibana password

3. **Source the devops environment**:
   ```bash
   source vars/contexts/devops/devops_env.sh
   ```

4. **Add bin directory to PATH**:
   ```bash
   export PATH="${PATH}:/home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin"
   ```

5. **Run the scripts**:
   ```bash
   # Now you can use esapi and kapi directly
   esapi GET /_cluster/health
   kapi GET /api/status
   
   # Or use full path
   /home/gxbrooks/repos/elastic-on-spark/observability/elasticsearch/bin/esapi GET /_cluster/health
   ```

## Examples

### Elasticsearch API Calls

```bash
# Get cluster health
esapi GET /_cluster/health

# Create an index template
esapi PUT /_index_template/my-template template.json

# Query an index
esapi GET /my-index/_search search.json
```

### Kibana API Calls

```bash
# Get Kibana status
kapi GET /api/status

# Create a data view
kapi POST /api/data_views/data_view dataview.json

# List all data views
kapi GET /api/data_views
```

## Dependencies

- Python 3.x
- `requests` module (for HTTP requests) - automatically installed by `assert_devops_client.sh`
- `pyyaml` module (for generate_env.py) - automatically installed by `assert_devops_client.sh`
- `toml` module (for generate_env.py) - automatically installed by `assert_devops_client.sh`

## Troubleshooting

### "ModuleNotFoundError: No module named 'requests'"

The `requests` module should be automatically installed when you run:
```bash
linux/assert_devops_client.sh -N <passphrase>
```

If you need to manually install it:
```bash
source venv/bin/activate
pip install requests
```

### "Error: Required environment variable not set"

Make sure you've sourced the devops environment:
```bash
source vars/contexts/devops/devops_env.sh
```

### "Error: CA certificate path does not exist"

Verify the CA certificate is installed at `/etc/ssl/certs/elastic/ca.crt` or update `CA_CERT` environment variable to point to the correct path.

