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

The scripts are automatically available in the `init-kibana` and `init-index` containers via the volume mount:
```yaml
volumes:
  - ./elasticsearch:/usr/share/elasticsearch/elasticsearch
```

The init scripts add the bin directory to PATH:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="${PATH}:${SCRIPT_DIR}"
```

### In Client Mode

For client mode usage (outside Docker containers), you need:

1. **Python 3 with requests module**:
   
   The `requests` module is automatically installed when you run `linux/assert_devops_client.sh`, which sets up the project venv with all required dependencies including `requests`, `pyyaml`, and `toml`.
   
   To manually install if needed:
   ```bash
   pip install requests
   ```

2. **Required environment variables** (automatically set when you source `linux/devops_env.sh`):
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
   source linux/devops_env.sh
   ```

4. **Run the scripts**:
   ```bash
   # Direct Python script usage
   observability/elasticsearch/bin/elastic_api.py elasticsearch GET /_cluster/health
   observability/elasticsearch/bin/elastic_api.py kibana GET /api/status
   
   # Via shell wrappers
   observability/elasticsearch/bin/esapi GET /_cluster/health
   observability/elasticsearch/bin/kapi GET /api/status
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

## Migration Notes

This refactoring (October 2024) simplified the implementation:

1. **Moved scripts** from `observability/shared/bin/` to `observability/elasticsearch/bin/`
2. **Consolidated Python code**: Combined `esapi.py`, `kapi.py`, `args.py`, and `api.py` into `elastic_api.py`
3. **Removed Docker detection**: No more `if [[ -f "/.dockerenv" ]]` checks or `docker compose exec` calls
4. **Simplified environment**: Scripts now use environment variables directly (no `PY_SCRIPTS` or `PYTHONPATH` needed)
5. **Updated docker-compose.yml**: Removed `/opt/shared` mount as it's no longer needed
6. **Updated variables.yaml**: Added `devops` context for client mode usage with `ELASTIC_HOST_CLIENT` and `KIBANA_HOST_CLIENT`
7. **Removed unused scripts**: Deleted `gapi` and all `*.old.sh` backup files

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
source linux/devops_env.sh
```

### "Error: CA certificate path does not exist"

Verify the CA certificate is installed at `/etc/ssl/certs/elastic/ca.crt` or update `CA_CERT` environment variable to point to the correct path.

