#!/usr/bin/env python3
"""
Data-Driven Variable Configuration Generator

Generates context-specific configuration files from centralized variable definitions.

Architecture:
  vars/variables.yaml  - Single source of truth for all variables
  vars/contexts.yaml   - Specification of output contexts and file formats
  generate_env.py - This script: transforms variables into context-specific files

Usage:
  ./generate_env.py                    # Generate all contexts
  ./generate_env.py spark-client       # Generate specific context
  ./generate_env.py -f                 # Force regeneration of all
  ./generate_env.py -v spark-image     # Verbose output for specific context
"""
import yaml
import os
import datetime
import sys
import argparse
from pathlib import Path

# Directory layout
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent

# Configuration files
VARIABLES_FILE = SCRIPT_DIR / 'variables.yaml'
CONTEXTS_FILE = SCRIPT_DIR / 'contexts.yaml'

# Type to writer function mapping
WRITER_FUNCTIONS = {
    'env': 'write_env',
    'shell_env': 'write_shell_env',
    'systemd_env': 'write_systemd_env',
    'toml': 'write_toml',
    'configmap': 'write_configmap',
    'ansible_vars': 'write_ansible_vars',
}


def load_variables():
    """Load variable definitions from vars/variables.yaml"""
    try:
        with VARIABLES_FILE.open() as f:
            return yaml.safe_load(f)
    except (yaml.YAMLError, IOError) as e:
        print(f"Error loading variables from {VARIABLES_FILE}: {e}")
        sys.exit(1)


def load_contexts():
    """Load context specifications from vars/contexts.yaml"""
    try:
        with CONTEXTS_FILE.open() as f:
            spec = yaml.safe_load(f)
            return spec.get('contexts', [])
    except (yaml.YAMLError, IOError) as e:
        print(f"Error loading contexts from {CONTEXTS_FILE}: {e}")
        sys.exit(1)


def validate_contexts(variables, contexts):
    """
    Validate that all contexts referenced in variables.yaml exist in contexts.yaml
    
    Args:
        variables: Dictionary of variable definitions
        contexts: List of context specifications from contexts.yaml
    
    Returns:
        List of warnings (empty if no issues found)
    """
    warnings = []
    
    # Build set of valid context names
    valid_context_names = {ctx['name'] for ctx in contexts}
    
    # Check each variable for invalid contexts
    for var_name, var_data in variables.items():
        if not isinstance(var_data, dict):
            continue
        
        # Get contexts list for this variable
        var_contexts = var_data.get('contexts', [])
        if not var_contexts:
            continue
        
        # Check each context referenced by this variable
        invalid_contexts = [ctx for ctx in var_contexts if ctx not in valid_context_names]
        if invalid_contexts:
            warnings.append(f"Variable '{var_name}' references undefined context(s): {', '.join(invalid_contexts)}")
        
        # Also check contexts in 'values' dictionary if present
        if 'values' in var_data:
            values_dict = var_data['values']
            # Check if any keys in values dict are contexts (not 'default')
            for key in values_dict.keys():
                if key != 'default' and key not in valid_context_names:
                    warnings.append(f"Variable '{var_name}' has context-specific value for undefined context: {key}")
    
    return warnings


def get_var_value(var_def, context_name):
    """Extract the value of a variable for a specific context"""
    if 'values' in var_def:
        values_dict = var_def['values']
        if context_name in values_dict:
            return values_dict[context_name]
        elif 'default' in values_dict:
            return values_dict['default']
        else:
            # No match and no default - use first available value as fallback
            return list(values_dict.values())[0] if values_dict else ''
    else:
        # Fall back to simple 'value' format
        return var_def.get('value', '')


def get_vars(variables, context_name):
    """Extract variables applicable to a specific context
    
    Supports two formats:
    1. Simple format: {'value': '...', 'contexts': [...]}
    2. Context-specific format: {'values': {'default': '...', 'context1': '...'}, 'contexts': [...]}
    
    Also supports linear variable expansion with context-specific references:
    - ${VAR_NAME} - references VAR_NAME in the current context
    - ${context:VAR_NAME} - references VAR_NAME in the specified context
    Variables are expanded in order - only earlier variables can be referenced by later ones.
    This prevents infinite recursion and ensures deterministic expansion.
    """
    import re
    
    # Extract variables in the order they appear in variables.yaml
    # This preserves the dependency order (earlier variables can be referenced by later ones)
    ordered_vars = []
    for k, v in variables.items():
        if context_name not in v.get('contexts', []):
            continue
        
        value = get_var_value(v, context_name)
        ordered_vars.append((k, value))
    
    # Linear expansion: process variables in order, expanding each using already-expanded variables
    # Pattern to match ${VAR_NAME} or ${context:VAR_NAME}
    # Group 1: context name (if present) or variable name
    # Group 2: variable name (if context prefix exists)
    pattern = r'\$\{([a-zA-Z_][a-zA-Z0-9_-]*)(?::([A-Z_][A-Z0-9_]*))?\}'
    expanded = {}
    
    for var_name, var_value in ordered_vars:
        if not isinstance(var_value, str):
            expanded[var_name] = var_value
            continue
        
        # Expand variable references using only already-expanded variables
        def replace_var(match):
            # Pattern captures: ${VAR_NAME} or ${context:VAR_NAME}
            # group(1) = context name (if group(2) exists) or variable name (if no group(2))
            # group(2) = variable name (if context prefix exists)
            if match.group(2):
                # Format: ${context:VAR_NAME}
                ref_context = match.group(1)
                ref_var_name = match.group(2)
                
                # Look up variable in specified context
                if ref_var_name in variables:
                    var_def = variables[ref_var_name]
                    if ref_context in var_def.get('contexts', []):
                        return str(get_var_value(var_def, ref_context))
                # Context or variable not found
                return match.group(0)
            else:
                # Format: ${VAR_NAME} - use current context
                ref_var_name = match.group(1)
                
                # First check if variable is already expanded in current context
                if ref_var_name in expanded:
                    return str(expanded[ref_var_name])
                
                # Variable not yet expanded (defined later) - return original to indicate error
                # This will help catch ordering issues
                return match.group(0)
        
        # Single pass expansion (linear, not recursive)
        expanded_value = re.sub(pattern, replace_var, var_value)
        
        # Warn if expansion failed (variable referenced before it's defined)
        if '${' in expanded_value:
            print(f"⚠ Warning: Variable '{var_name}' references undefined or later-defined variable in: {expanded_value}")
        
        expanded[var_name] = expanded_value
    
    return expanded


def write_env(vars_dict, filename):
    """Write environment variables to a file in KEY=VALUE format (no export)"""
    try:
        with open(filename, 'w') as f:
            f.write('# This file is automatically generated from vars/variables.yaml by vars/generate_env.py\n')
            f.write('# Do not edit manually!\n\n')
            for k, v in vars_dict.items():
                f.write(f'{k}={v}\n')
        return True
    except IOError as e:
        print(f"Error writing to {filename}: {e}")
        return False


def write_shell_env(vars_dict, filename):
    """Write variables to shell environment file with export statements"""
    try:
        with open(filename, 'w') as f:
            f.write('# This file is automatically generated from vars/variables.yaml by vars/generate_env.py\n')
            f.write('# Do not edit manually!\n\n')
            
            for k, v in vars_dict.items():
                f.write(f'export {k}="{v}"\n')
        return True
    except IOError as e:
        print(f"Error writing to {filename}: {e}")
        return False


def write_systemd_env(vars_dict, filename):
    """Write variables to systemd EnvironmentFile format (Environment="KEY=VALUE")"""
    try:
        with open(filename, 'w') as f:
            f.write('# This file is automatically generated from vars/variables.yaml by vars/generate_env.py\n')
            f.write('# Do not edit manually!\n\n')
            
            for k, v in vars_dict.items():
                # Escape quotes in values for systemd
                escaped_value = str(v).replace('"', '\\"')
                f.write(f'Environment={k}="{escaped_value}"\n')
        return True
    except IOError as e:
        print(f"Error writing to {filename}: {e}")
        return False


def write_toml(vars_dict, filename):
    """Write environment variables to a TOML file"""
    try:
        with open(filename, 'w') as f:
            f.write('# This file is automatically generated from vars/variables.yaml by vars/generate_env.py\n')
            f.write('# Do not edit manually!\n\n')
            f.write('[env]\n')
            for k, v in vars_dict.items():
                if isinstance(v, str):
                    f.write(f'{k} = "{v}"\n')
                else:
                    f.write(f'{k} = {v}\n')
        return True
    except IOError as e:
        print(f"Error writing to {filename}: {e}")
        return False


def write_configmap(vars_dict, filename):
    """Write environment variables to a Kubernetes ConfigMap YAML file"""
    try:
        with open(filename, 'w') as f:
            f.write('# This file is automatically generated from vars/variables.yaml by vars/generate_env.py\n')
            f.write('# Do not edit manually!\n\n')
            f.write('apiVersion: v1\n')
            f.write('kind: ConfigMap\n')
            f.write('metadata:\n')
            f.write('  name: spark-configmap\n')
            f.write('  namespace: spark\n')
            f.write('data:\n')
            for k, v in vars_dict.items():
                f.write(f'  {k}: "{v}"\n')
        return True
    except IOError as e:
        print(f"Error writing to {filename}: {e}")
        return False


def write_ansible_vars(vars_dict, filename):
    """Write variables to Ansible variables YAML file with structured formatting"""
    try:
        with open(filename, 'w') as f:
            f.write('# Centralized variables for Ansible playbooks and roles\n')
            f.write('# This file is automatically generated from vars/variables.yaml by vars/generate_env.py\n')
            f.write('# Do not edit manually!\n\n')
            
            # Write Spark version first if it exists
            if 'SPARK_VERSION' in vars_dict:
                f.write(f'# Spark version\nspark_version: "{vars_dict["SPARK_VERSION"]}"\n\n')
              
            # Write registry configuration
            f.write('# Registry and image configuration (using local registry on Lab2)\n')
            f.write('registry_host: "lab2.local:5000"\n')
            f.write('spark_image: "{{ registry_host }}/spark"\n')
            f.write('spark_tag: "{{ spark_version }}"\n\n')
              
            # Write paths and directories
            f.write('# Paths and directories\n')
            if 'SPARK_EVENTS_DIR' in vars_dict:
                f.write(f'spark_events_dir: "{vars_dict["SPARK_EVENTS_DIR"]}"\n')
            if 'SPARK_HOME' in vars_dict:
                f.write(f'spark_home: "{vars_dict["SPARK_HOME"]}"\n')
            f.write('\n')
            
            # Write Elastic related settings
            elastic_vars = {k: v for k, v in vars_dict.items() if k.startswith('ELASTIC_')}
            if elastic_vars:
                f.write('# Elasticsearch settings\n')
                for key, value in elastic_vars.items():
                    var_name = key.lower()
                    f.write(f'{var_name}: "{value}"\n')
                f.write('\n')
            
            # Write Kubernetes settings
            f.write('# Kubernetes-specific settings\n')
            f.write('k8s_namespace: "spark"\n')
        return True
    except IOError as e:
        print(f"Error writing to {filename}: {e}")
        return False


def needs_update(source_files, target_file):
    """
    Check if target file needs to be updated by comparing modification times
    
    Args:
        source_files: List of source files to check (vars/variables.yaml, vars/contexts.yaml)
        target_file: The generated file to check
    
    Returns:
        String describing why update is needed, or False if up to date
    """
    # If target doesn't exist, it needs to be created
    if not target_file.exists():
        return "Target file does not exist"
    
    # Check if any source file is newer than target
    try:
        target_mtime = target_file.stat().st_mtime
        
        for source_file in source_files:
            if not source_file.exists():
                continue
                
            source_mtime = source_file.stat().st_mtime
            
            if source_mtime > target_mtime:
                source_time = datetime.datetime.fromtimestamp(source_mtime).isoformat()
                target_time = datetime.datetime.fromtimestamp(target_mtime).isoformat()
                return f"Source file {source_file} ({source_time}) is newer than target ({target_time})"
    except OSError as e:
        return f"Error checking file timestamps: {e}"
    
    return False


def main(requested_contexts=None, force=False, verbose=False):
    """
    Main entry point for variable generation
    
    Args:
        requested_contexts: List of context names to generate (None = all)
        force: Force regeneration even if files are up to date
        verbose: Show verbose output
    
    Returns:
        0 on success, 1 on error
    """
    # Load configuration
    variables = load_variables()
    contexts = load_contexts()
    
    if not contexts:
        print(f"No contexts defined in {CONTEXTS_FILE}")
        return 1
    
    # Validate that all contexts referenced in variables exist in contexts.yaml
    context_warnings = validate_contexts(variables, contexts)
    if context_warnings:
        print("⚠ Warning: Variables reference undefined contexts:")
        for warning in context_warnings:
            print(f"  {warning}")
        print()
    
    # Build context lookup by name
    context_map = {ctx['name']: ctx for ctx in contexts}
    
    # Determine which contexts to generate
    if requested_contexts:
        # Validate requested contexts
        invalid_contexts = [c for c in requested_contexts if c not in context_map]
        if invalid_contexts:
            print(f"Error: Unknown context(s): {', '.join(invalid_contexts)}")
            print(f"Available contexts: {', '.join(context_map.keys())}")
            return 1
        contexts_to_generate = [context_map[c] for c in requested_contexts]
    else:
        # Generate all contexts
        contexts_to_generate = contexts
    
    # Source files for timestamp checking
    source_files = [VARIABLES_FILE, CONTEXTS_FILE]
    
    # Track results
    changes_made = False
    errors = []
    
    # Generate each context
    for context in contexts_to_generate:
        context_name = context['name']
        output_type = context['type']
        output_file = context['output']
        # All paths in contexts.yaml are relative to vars/contexts/ by default
        # If path doesn't start with vars/, assume it's relative to vars/contexts/
        if not output_file.startswith('vars/'):
            output_path = (REPO_ROOT / 'vars' / 'contexts' / output_file).resolve()
        else:
            output_path = (REPO_ROOT / output_file).resolve()
        description = context.get('description', 'No description')
        
        # Validate output type
        if output_type not in WRITER_FUNCTIONS:
            print(f"Error: Unknown output type '{output_type}' for context '{context_name}'")
            print(f"Supported types: {', '.join(WRITER_FUNCTIONS.keys())}")
            errors.append(context_name)
            continue
        
        # Check if update is needed
        update_reason = needs_update(source_files, output_path) if not force else "Force flag set"
        
        if not force and not update_reason:
            if verbose:
                print(f"✓ Skipping {output_file} (up to date)")
            continue
        
        # Display what we're doing
        if force:
            print(f"→ Generating {output_path} for context '{context_name}' (forced)")
        else:
            print(f"→ Generating {output_path} for context '{context_name}'")
            if verbose:
                print(f"  Reason: {update_reason}")
                print(f"  Type: {output_type}")
                print(f"  Description: {description}")
        
        # Ensure output directory exists
        output_dir = output_path.parent
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Extract variables for this context
        vars_dict = get_vars(variables, context_name)
        
        if verbose:
            print(f"  Variables: {len(vars_dict)} extracted")
        
        # Get the writer function
        writer_func_name = WRITER_FUNCTIONS[output_type]
        writer_func = globals()[writer_func_name]
        
        # Generate the file
        success = writer_func(vars_dict, str(output_path))
        
        if success:
            changes_made = True
            print(f"✓ Successfully generated {output_file}")
        else:
            print(f"✗ Failed to generate {output_file}")
            errors.append(context_name)
    
    # Summary
    if errors:
        print(f"\n✗ Completed with {len(errors)} error(s): {', '.join(errors)}")
        return 1
    elif changes_made:
        print(f"\n✓ All requested files generated successfully")
        return 0
    else:
        print(f"\n✓ All files up to date")
        return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Generate context-specific configuration files from centralized variables',
        epilog='Examples:\n'
               '  %(prog)s                    # Generate all contexts\n'
               '  %(prog)s spark-client       # Generate specific context\n'
               '  %(prog)s -f                 # Force regeneration\n'
               '  %(prog)s -v spark-image     # Verbose output\n',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        'contexts',
        nargs='*',
        help='Contexts to generate (if none specified, all will be generated)'
    )
    parser.add_argument(
        '-f', '--force',
        action='store_true',
        help='Force regeneration even if files are up to date'
    )
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Show verbose output'
    )
    
    args = parser.parse_args()
    
    contexts = args.contexts if args.contexts else None
    result = main(contexts, args.force, args.verbose)
    sys.exit(result)
