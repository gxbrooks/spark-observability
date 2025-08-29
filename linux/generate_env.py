#!/usr/bin/env python3
"""
Script to generate context-specific env/config files from config.env.yaml
- docker/.env
- spark/spark-image.toml
- sparif __name__ == '__main__':
    import sys
    import argparse
    
    parser = argparse.ArgumentParser(description='Generate environment configuration files')
    parser.add_argument('contexts', nargs='*', help='Contexts to generate (if none specified, all will be generated)')
    parser.add_argument('-f', '--force', action='store_true', help='Force regeneration even if files are up to date')
    parser.add_argument('-v', '--verbose', action='store_true', help='Show verbose output')
    
    args = parser.parse_args()
    
    contexts = args.contexts if args.contexts else None
    result = main(contexts, args.force)
    sys.exit(result)configmap.yaml
"""
import yaml
import toml

CONFIG_FILE = 'variables.yaml'

# Contexts and output files
CONTEXTS = {
    'observability': 'docker/.env',
    'spark-image': 'spark/spark-image.toml',
    'spark-runtime': 'spark/k8s/spark-configmap.yaml',
}

def load_config():
    with open(CONFIG_FILE) as f:
        return yaml.safe_load(f)

def get_vars(config, context):
    return {k: v['value'] for k, v in config.items() if context in v['contexts']}

def write_env(vars_dict, filename):
    """Write environment variables to a file in KEY=VALUE format"""
    try:
        with open(filename, 'w') as f:
            for k, v in vars_dict.items():
                f.write(f'{k}={v}\n')
    except IOError as e:
        print(f"Error writing to {filename}: {e}")
        return False
    return True

def write_toml(vars_dict, filename):
    """Write environment variables to a TOML file"""
    try:
        with open(filename, 'w') as f:
            toml.dump({'env': vars_dict}, f)
    except IOError as e:
        print(f"Error writing to {filename}: {e}")
        return False
    return True

def write_configmap(vars_dict, filename):
    """Write environment variables to a Kubernetes ConfigMap YAML file"""
    try:
        with open(filename, 'w') as f:
            f.write('apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: spark-configmap\n  namespace: spark\ndata:\n')
            for k, v in vars_dict.items():
                f.write(f'  {k}: "{v}"\n')
    except IOError as e:
        print(f"Error writing to {filename}: {e}")
        return False
    return True

def needs_update(source_file, target_file):
    """Check if target file needs to be updated by comparing modification times"""
    import os.path
    import datetime
    
    # If target doesn't exist, it needs to be created
    if not os.path.exists(target_file):
        return "Target file does not exist"
        
    # Check if source is newer than target
    try:
        source_mtime = os.path.getmtime(source_file)
        target_mtime = os.path.getmtime(target_file)
        
        if source_mtime > target_mtime:
            source_time = datetime.datetime.fromtimestamp(source_mtime).isoformat()
            target_time = datetime.datetime.fromtimestamp(target_mtime).isoformat()
            return f"Source file ({source_time}) is newer than target ({target_time})"
    except OSError as e:
        return f"Error checking file timestamps: {e}"
    
    return False

def main(contexts=None, force=False, verbose=False):
    try:
        config = load_config()
    except (yaml.YAMLError, IOError) as e:
        print(f"Error loading configuration from {CONFIG_FILE}: {e}")
        return 1
    
    # If no contexts specified, generate all
    if contexts is None:
        contexts = CONTEXTS.keys()
    
    changes_made = False
    
    for context in contexts:
        if context not in CONTEXTS:
            print(f"Warning: Unknown context {context}")
            continue
        
        target_file = CONTEXTS[context]
        
        # Check if update is needed
        update_reason = needs_update(CONFIG_FILE, target_file) if not force else "Force flag set"
        
        if force or update_reason:
            if force:
                print(f"Generating {target_file} for context {context} (forced)")
            else:
                print(f"Generating {target_file} for context {context} - {update_reason}")
            
            # Ensure directory exists
            import os
            os.makedirs(os.path.dirname(target_file), exist_ok=True)
            
            # Get variables for this context
            vars_dict = get_vars(config, context)
            
            success = False
            if context == 'observability':
                success = write_env(vars_dict, target_file)
            elif context == 'spark-image':
                success = write_toml(vars_dict, target_file)
            elif context == 'spark-runtime':
                success = write_configmap(vars_dict, target_file)
            
            if success:
                changes_made = True
                if verbose:
                    print(f"Successfully generated {target_file}")
        else:
            print(f"Skipping {target_file} (up to date)")
    
    return 0

if __name__ == '__main__':
    import sys
    import argparse
    
    parser = argparse.ArgumentParser(description='Generate environment configuration files')
    parser.add_argument('contexts', nargs='*', help='Contexts to generate (if none specified, all will be generated)')
    parser.add_argument('-f', '--force', action='store_true', help='Force regeneration even if files are up to date')
    parser.add_argument('-v', '--verbose', action='store_true', help='Show verbose output')
    
    args = parser.parse_args()
    
    contexts = args.contexts if args.contexts else None
    result = main(contexts, args.force, args.verbose)
    sys.exit(result)
