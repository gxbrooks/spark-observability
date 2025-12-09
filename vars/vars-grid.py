#!/usr/bin/env python3
"""
Variable-Context Grid Generator

Generates a grid showing which variables are used in which contexts.
This helps identify:
- Variables that appear in many contexts (potential candidates for consolidation)
- Contexts with very few variables (potential candidates for removal)
- Variables that appear in only one context (may be context-specific)
- Missing context definitions

Usage:
    # Recommended - use wrapper script (uses system Python)
    bash vars/vars-grid.sh                    # Generate grid for all contexts
    bash vars/vars-grid.sh --missing          # Show only missing contexts
    bash vars/vars-grid.sh --summary          # Show summary statistics
    bash vars/vars-grid.sh -c devops,spark-client  # Show grid for specific contexts
    
    # Or directly (requires PyYAML installed)
    python3 vars/vars-grid.py                    # Generate grid for all contexts
    python3 vars/vars-grid.py --missing          # Show only missing contexts
    python3 vars/vars-grid.py --summary          # Show summary statistics
    python3 vars/vars-grid.py -c devops,spark-client -ov  # Show only variables in one or more specified contexts
    python3 vars/vars-grid.py -ov  # Show only variables in ALL contexts
    python3 vars/vars-grid.py -oc  # Omit context columns that have no variables
    python3 vars/vars-grid.py -ov -oc  # Combine both filters
    python3 vars/vars-grid.py -v "^ES_"  # Show only variables matching regex pattern
    python3 vars/vars-grid.py -v "SPARK_.*"  # Show variables starting with SPARK_ (note: use .* not *)
    python3 vars/vars-grid.py -c devops -v "SPARK"  # Combine context and variable filters
"""

import yaml
import sys
import argparse
import re
from pathlib import Path

# Directory layout
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent

# Configuration files
VARIABLES_FILE = SCRIPT_DIR / 'variables.yaml'
CONTEXTS_FILE = SCRIPT_DIR / 'contexts.yaml'


def load_variables():
    """Load variable definitions from vars/variables.yaml"""
    try:
        with VARIABLES_FILE.open() as f:
            return yaml.safe_load(f)
    except (yaml.YAMLError, IOError) as e:
        print(f"Error loading variables from {VARIABLES_FILE}: {e}", file=sys.stderr)
        sys.exit(1)


def load_contexts():
    """Load context specifications from vars/contexts.yaml"""
    try:
        with CONTEXTS_FILE.open() as f:
            spec = yaml.safe_load(f)
            return [ctx['name'] for ctx in spec.get('contexts', [])]
    except (yaml.YAMLError, IOError) as e:
        print(f"Error loading contexts from {CONTEXTS_FILE}: {e}", file=sys.stderr)
        sys.exit(1)


def generate_grid(variables, contexts, show_missing=False, filter_contexts=None, omit_vars=False, omit_columns=False, var_pattern=None):
    """Generate variable-context grid"""
    # Collect all contexts mentioned in variables
    all_contexts_in_vars = set()
    for var_name, var_data in variables.items():
        if isinstance(var_data, dict) and 'contexts' in var_data:
            all_contexts_in_vars.update(var_data['contexts'])
    
    # Combine contexts from contexts.yaml and variables.yaml
    all_contexts = sorted(set(contexts + list(all_contexts_in_vars)))
    
    # Filter contexts if specified
    filter_set = None
    if filter_contexts:
        filter_set = set(filter_contexts)
        # Validate that all requested contexts exist
        invalid_contexts = filter_set - set(all_contexts)
        if invalid_contexts:
            print(f"Error: Unknown context(s): {', '.join(sorted(invalid_contexts))}", file=sys.stderr)
            print(f"Available contexts: {', '.join(sorted(all_contexts))}", file=sys.stderr)
            sys.exit(1)
    
    # Compile regex pattern if provided
    var_regex = None
    if var_pattern:
        try:
            var_regex = re.compile(var_pattern)
        except re.error as e:
            print(f"Error: Invalid regular expression '{var_pattern}': {e}", file=sys.stderr)
            sys.exit(1)
    
    # Find missing contexts (in variables.yaml but not in contexts.yaml)
    missing_contexts = all_contexts_in_vars - set(contexts)
    
    if show_missing:
        if missing_contexts:
            print("Contexts in variables.yaml but not in contexts.yaml:")
            for ctx in sorted(missing_contexts):
                print(f"  - {ctx}")
        else:
            print("All contexts in variables.yaml are defined in contexts.yaml")
        return
    
    # First pass: collect filtered variables to determine which contexts to show
    filtered_variables = {}
    contexts_with_variables = set()
    
    for var_name in sorted(variables.keys()):
        # Apply variable name regex filter if provided
        if var_regex and not var_regex.search(var_name):
            continue
        
        var_data = variables[var_name]
        
        # Get contexts for this variable (empty list if not a dict or no contexts)
        var_contexts = []
        if isinstance(var_data, dict) and 'contexts' in var_data:
            var_contexts = var_data['contexts']
        
        # Apply filtering logic only if -ov flag is used
        if omit_vars:
            if filter_contexts:
                # Show variables that appear in one or more of the specified contexts
                if not any(ctx in var_contexts for ctx in filter_contexts):
                    continue
            else:
                # Show variables that appear in ALL contexts (only check contexts defined in contexts.yaml)
                if not all(ctx in var_contexts for ctx in contexts):
                    continue
        
        # This variable passed all filters, include it
        filtered_variables[var_name] = var_data
        contexts_with_variables.update(var_contexts)
    
    # Determine which context columns to display
    if omit_columns:
        # Only show contexts that have at least one filtered variable
        if filter_contexts:
            # Only show the specified contexts that have at least one variable
            display_contexts = sorted(set(filter_contexts) & contexts_with_variables)
        else:
            # Show all contexts that have at least one variable
            display_contexts = sorted(contexts_with_variables)
    else:
        # Show all contexts (or filtered contexts if -c was used)
        if filter_contexts:
            display_contexts = sorted(filter_set)
        else:
            display_contexts = all_contexts
    
    # Handle empty display_contexts (no variables matched filters)
    if not display_contexts:
        print("Variable-Context Grid:")
        filters = []
        if omit_vars:
            if filter_contexts:
                filters.append(f"variables in one or more of: {', '.join(filter_contexts)}")
            else:
                filters.append("variables in ALL contexts")
        elif filter_contexts:
            filters.append(f"contexts: {', '.join(filter_contexts)}")
        if omit_columns:
            filters.append("omit empty columns")
        if var_pattern:
            filters.append(f"variable name matches: {var_pattern}")
        if filters:
            print(f"({', '.join(filters)})")
        print("\nNo variables match the specified filters.")
        return
    
    # Build grid
    print("Variable-Context Grid:")
    filters = []
    if omit_vars:
        if filter_contexts:
            filters.append(f"variables in one or more of: {', '.join(filter_contexts)}")
        else:
            filters.append("variables in ALL contexts")
    elif filter_contexts:
        filters.append(f"contexts: {', '.join(filter_contexts)}")
    if omit_columns:
        filters.append("omit empty columns")
    if var_pattern:
        filters.append(f"variable name matches: {var_pattern}")
    if filters:
        print(f"({', '.join(filters)})")
    
    # Column widths
    VAR_COL_WIDTH = 35
    CTX_COL_WIDTH = 15
    
    # Helper function to wrap context names at punctuation marks
    def wrap_context_name(name, max_width):
        """Wrap context name at punctuation marks if it exceeds max_width"""
        if len(name) <= max_width:
            return [name]
        
        # Try to break at punctuation marks (dash, underscore, dot)
        for sep in ['-', '_', '.']:
            if sep in name:
                parts = name.split(sep)
                result = []
                current = parts[0]
                for part in parts[1:]:
                    if len(current) + len(sep) + len(part) <= max_width:
                        current += sep + part
                    else:
                        if current:
                            result.append(current)
                        current = part
                if current:
                    result.append(current)
                if len(result) > 1:
                    return result
        
        # If no punctuation found or wrapping didn't help, break at max_width
        result = []
        for i in range(0, len(name), max_width):
            result.append(name[i:i+max_width])
        return result
    
    # Prepare wrapped context headers
    wrapped_headers = {}
    max_header_lines = 1
    for ctx in display_contexts:
        wrapped = wrap_context_name(ctx, CTX_COL_WIDTH)
        wrapped_headers[ctx] = wrapped
        max_header_lines = max(max_header_lines, len(wrapped))
    
    # Calculate total width for separator
    total_width = VAR_COL_WIDTH + len(display_contexts) * CTX_COL_WIDTH
    print("=" * total_width)
    
    # Build set of valid contexts from contexts.yaml
    valid_contexts_set = set(contexts)
    
    # Header - print wrapped context names line by line
    for line_num in range(max_header_lines):
        if line_num == 0:
            # First line: show "Variable" label
            print(f"{'Variable':<{VAR_COL_WIDTH}}", end='')
        else:
            # Subsequent lines: blank space for variable column
            print(' ' * VAR_COL_WIDTH, end='')
        
        # Print each context's header line (or blank if no more lines)
        for ctx in display_contexts:
            wrapped = wrapped_headers[ctx]
            if line_num < len(wrapped):
                print(f'{wrapped[line_num].center(CTX_COL_WIDTH)}', end='')
            else:
                print(' ' * CTX_COL_WIDTH, end='')
        print()
    
    # Separator
    print('-' * total_width)
    
    # Grid rows - only show filtered variables
    for var_name in sorted(filtered_variables.keys()):
        var_data = filtered_variables[var_name]
        
        # Truncate variable name if too long
        display_var_name = var_name[:VAR_COL_WIDTH] if len(var_name) <= VAR_COL_WIDTH else var_name[:VAR_COL_WIDTH-3] + '...'
        
        # Get contexts for this variable (empty list if not a dict or no contexts)
        var_contexts = []
        if isinstance(var_data, dict) and 'contexts' in var_data:
            var_contexts = var_data['contexts']
        
        # Show the variable
        print(f'{display_var_name:<{VAR_COL_WIDTH}}', end='')
        for ctx in display_contexts:
            if ctx in var_contexts:
                print('X'.center(CTX_COL_WIDTH), end='')
            else:
                print(' '.center(CTX_COL_WIDTH), end='')
        print()
    
    # Show missing contexts warning if any displayed contexts are not in contexts.yaml
    displayed_missing = [ctx for ctx in display_contexts if ctx not in valid_contexts_set]
    if displayed_missing:
        print(f'\n⚠ Warning: Contexts in variables.yaml but not in contexts.yaml: {sorted(displayed_missing)}')
    
    # Also show warning for all missing contexts if not filtering
    if missing_contexts and not filter_contexts:
        all_missing = sorted(missing_contexts - set(display_contexts))
        if all_missing:
            print(f'⚠ Warning: Additional contexts in variables.yaml but not in contexts.yaml: {all_missing}')


def generate_summary(variables, contexts):
    """Generate summary statistics"""
    # Collect all contexts mentioned in variables
    all_contexts_in_vars = set()
    for var_name, var_data in variables.items():
        if isinstance(var_data, dict) and 'contexts' in var_data:
            all_contexts_in_vars.update(var_data['contexts'])
    
    # Count variables per context
    context_counts = {}
    for var_name, var_data in variables.items():
        if isinstance(var_data, dict) and 'contexts' in var_data:
            for ctx in var_data['contexts']:
                context_counts[ctx] = context_counts.get(ctx, 0) + 1
    
    # Count contexts per variable
    variable_context_counts = {}
    for var_name, var_data in variables.items():
        if isinstance(var_data, dict) and 'contexts' in var_data:
            count = len(var_data['contexts'])
            variable_context_counts[var_name] = count
    
    print("Summary Statistics:")
    print("=" * 60)
    print(f"Total variables: {len(variables)}")
    print(f"Total contexts in contexts.yaml: {len(contexts)}")
    print(f"Total contexts referenced in variables.yaml: {len(all_contexts_in_vars)}")
    
    missing_contexts = all_contexts_in_vars - set(contexts)
    if missing_contexts:
        print(f"Missing contexts (in variables.yaml but not contexts.yaml): {len(missing_contexts)}")
        print(f"  {sorted(missing_contexts)}")
    else:
        print("✓ All contexts in variables.yaml are defined in contexts.yaml")
    
    print("\nContext Usage (variables per context):")
    print("-" * 60)
    for ctx in sorted(context_counts.keys(), key=lambda x: context_counts[x], reverse=True):
        status = "✓" if ctx in contexts else "⚠"
        print(f"{status} {ctx:<30} {context_counts[ctx]:>3} variables")
    
    print("\nVariable Usage (contexts per variable):")
    print("-" * 60)
    # Group by count
    by_count = {}
    for var_name, count in variable_context_counts.items():
        if count not in by_count:
            by_count[count] = []
        by_count[count].append(var_name)
    
    for count in sorted(by_count.keys(), reverse=True):
        vars_list = sorted(by_count[count])
        print(f"\nVariables used in {count} context(s):")
        for var_name in vars_list:
            print(f"  - {var_name}")


def main():
    parser = argparse.ArgumentParser(
        description="Generate variable-context grid and analysis",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        '--missing',
        action='store_true',
        help='Show only missing context definitions'
    )
    parser.add_argument(
        '--summary',
        action='store_true',
        help='Show summary statistics instead of grid'
    )
    parser.add_argument(
        '-c', '--contexts',
        type=str,
        help='Comma-separated list of context names to filter the grid (e.g., "devops,spark-client")'
    )
    parser.add_argument(
        '-ov', '--omit-vars',
        action='store_true',
        help='Only show variables in specified contexts: with -c shows variables in one or more specified contexts; without -c shows variables in ALL contexts defined in contexts.yaml (note: this is very restrictive - most variables won\'t match)'
    )
    parser.add_argument(
        '-oc', '--omit-columns',
        action='store_true',
        help='Omit context columns that do not have one or more variables specified'
    )
    parser.add_argument(
        '-v', '--vars',
        type=str,
        metavar='PATTERN',
        help='Regular expression to filter variable names (e.g., "^ES_" for variables starting with ES_)'
    )
    
    args = parser.parse_args()
    
    # Load data
    variables = load_variables()
    contexts = load_contexts()
    
    # Parse context filter if provided
    filter_contexts = None
    if args.contexts:
        filter_contexts = [ctx.strip() for ctx in args.contexts.split(',')]
    
    # Generate output
    if args.summary:
        generate_summary(variables, contexts)
    elif args.missing:
        generate_grid(variables, contexts, show_missing=True)
    else:
        generate_grid(variables, contexts, filter_contexts=filter_contexts, omit_vars=args.omit_vars, omit_columns=args.omit_columns, var_pattern=args.vars)


if __name__ == '__main__':
    main()

