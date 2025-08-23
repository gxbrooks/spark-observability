#!/usr/bin/env python3
"""
Script to generate context-specific env/config files from config.env.yaml
- docker/.env
- spark/spark-image.toml
- spark/k8s/spark-configmap.yaml
"""
import yaml
import toml

CONFIG_FILE = '../variables.yaml'

# Contexts and output files
CONTEXTS = {
    'observability': '../docker/.env',
    'spark-image': '../spark/spark-image.toml',
    'spark-runtime': '../spark/k8s/spark-configmap.yaml',
}

def load_config():
    with open(CONFIG_FILE) as f:
        return yaml.safe_load(f)

def get_vars(config, context):
    return {k: v['value'] for k, v in config.items() if context in v['contexts']}

def write_env(vars_dict, filename):
    with open(filename, 'w') as f:
        for k, v in vars_dict.items():
            f.write(f'{k}={v}\n')

def write_toml(vars_dict, filename):
    with open(filename, 'w') as f:
        toml.dump({'env': vars_dict}, f)

def write_configmap(vars_dict, filename):
    with open(filename, 'w') as f:
        f.write('apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: spark-env\n  namespace: spark\ndata:\n')
        for k, v in vars_dict.items():
            f.write(f'  {k}: "{v}"\n')

def main():
    config = load_config()
    # Observability context (.env for Docker Compose)
    obs_vars = get_vars(config, 'observability')
    write_env(obs_vars, CONTEXTS['observability'])
    # Spark image context (TOML for image build)
    img_vars = get_vars(config, 'spark-image')
    write_toml(img_vars, CONTEXTS['spark-image'])
    # Spark runtime context (K8s ConfigMap)
    rt_vars = get_vars(config, 'spark-runtime')
    write_configmap(rt_vars, CONTEXTS['spark-runtime'])

if __name__ == '__main__':
    main()
