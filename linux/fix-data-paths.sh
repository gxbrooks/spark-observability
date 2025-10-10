#!/bin/bash

# Fix data paths in Spark code files
# This script updates all references from ./data/ to /mnt/spark/data/

# Parse arguments
DEBUG=false
CHECK=false

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d)
            DEBUG=true
            ;;
        --Check|-c)
            CHECK=true
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c]"
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Debug   : Starting data path fixes..."
$DEBUG && echo "Debug   : root_dir = $root_dir"

# Function to fix paths in a file
fix_file_paths() {
    local file="$1"
    $DEBUG && echo "Debug   : Processing file: $file"
    
    if [ ! -f "$file" ]; then
        echo "Warning : File not found: $file"
        return 1
    fi
    
    # Check if file contains old paths
    if grep -q "\./data/" "$file"; then
        if $CHECK; then
            echo "Check   : File $file contains old paths - would update"
        else
            echo "Info    : Updating paths in $file..."
            # Replace ./data/ with /mnt/spark/data/
            sed -i 's|\./data/|/mnt/spark/data/|g' "$file"
            echo "Success : Updated paths in $file"
        fi
    else
        $DEBUG && echo "Debug   : File $file does not contain old paths"
    fi
}

# Find all Python files in spark directory that might contain old paths
$DEBUG && echo "Debug   : Searching for files with old data paths..."

# Get list of files with old paths
files_with_old_paths=$(grep -r "\./data/" "$root_dir/spark" --include="*.py" -l 2>/dev/null || true)

if [ -z "$files_with_old_paths" ]; then
    echo "Info    : No files found with old data paths"
    exit 0
fi

echo "Info    : Found files with old data paths:"
echo "$files_with_old_paths" | while read -r file; do
    echo "  - $file"
done

if $CHECK; then
    echo "Check   : Would update paths in $(echo "$files_with_old_paths" | wc -l) files"
    exit 0
fi

# Process each file
echo "$files_with_old_paths" | while read -r file; do
    fix_file_paths "$file"
done

echo "Result  : Data path fixes completed successfully"
