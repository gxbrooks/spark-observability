#!/bin/bash

# Assert Spark Client Applications
# This script verifies the installation and configuration of Spark client applications
# for both batch (Python scripts) and interactive (iPython) modes.
#
# Usage: ./assert_spark_client_apps.sh [--Debug|-d] [--Check|-c] [--Fix|-f]

# Parse arguments
DEBUG=false
CHECK=false
FIX=false

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
        --Fix|-f)
            FIX=true
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." 
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--Fix|-f]"
            echo ""
            echo "Options:"
            echo "  --Debug|-d   : Enable debug output"
            echo "  --Check|-c   : Check mode - report what would be done without making changes"
            echo "  --Fix|-f     : Automatically fix issues (install missing components)"
            exit 1
            ;;
    esac
    shift
done

$DEBUG && echo "Starting: $script_name"
$DEBUG && echo "Root directory: $root_dir"
$DEBUG && echo "Mode: $([ "$CHECK" = true ] && echo "CHECK" || echo "EXECUTE")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track overall status
ISSUES_FOUND=0
CHECKS_PASSED=0
CHECKS_FAILED=0

# Function to report check results
report_check() {
    local status=$1
    local message=$2
    
    if [ "$status" = "pass" ]; then
        echo -e "${GREEN}✓ Pass${NC}   : $message"
        ((CHECKS_PASSED++))
    elif [ "$status" = "fail" ]; then
        echo -e "${RED}✗ Fail${NC}   : $message"
        ((CHECKS_FAILED++))
        ((ISSUES_FOUND++))
    elif [ "$status" = "warn" ]; then
        echo -e "${YELLOW}⚠ Warn${NC}   : $message"
    elif [ "$status" = "info" ]; then
        echo -e "${BLUE}ℹ Info${NC}   : $message"
    fi
}

# Check if Python 3.8 is available
check_python38() {
    $DEBUG && echo "Debug   : Checking for Python 3.8..."
    
    if command -v python3.8 >/dev/null 2>&1; then
        local version=$(python3.8 --version 2>&1)
        report_check "pass" "Python 3.8 found: $version"
        return 0
    else
        report_check "fail" "Python 3.8 not found (required for Spark 3.5.1 compatibility)"
        if $FIX && ! $CHECK; then
            echo "Info    : Installing Python 3.8..."
            "$script_dir/assert_python_version.sh" --PythonVersion 3.8
        elif $CHECK; then
            echo "Check   : Would install Python 3.8 using assert_python_version.sh"
        fi
        return 1
    fi
}

# Check if virtual environment exists
check_venv() {
    $DEBUG && echo "Debug   : Checking for virtual environment..."
    
    local venv_dir="${root_dir}/venv"
    
    if [ -d "$venv_dir" ] && [ -f "$venv_dir/bin/activate" ]; then
        report_check "pass" "Virtual environment exists at $venv_dir"
        return 0
    else
        report_check "fail" "Virtual environment not found at $venv_dir"
        if $FIX && ! $CHECK; then
            echo "Info    : Creating virtual environment..."
            "$script_dir/assert_python_version.sh" --PythonVersion 3.8 --SetupVenv
        elif $CHECK; then
            echo "Check   : Would create virtual environment using assert_python_version.sh"
        fi
        return 1
    fi
}

# Check if PySpark is installed in venv
check_pyspark() {
    $DEBUG && echo "Debug   : Checking for PySpark installation..."
    
    local venv_dir="${root_dir}/venv"
    
    if [ -d "$venv_dir" ]; then
        # Check if PySpark is installed
        if "$venv_dir/bin/python" -c "import pyspark" 2>/dev/null; then
            local pyspark_version=$("$venv_dir/bin/python" -c "import pyspark; print(pyspark.__version__)" 2>/dev/null)
            report_check "pass" "PySpark installed in venv: version $pyspark_version"
            return 0
        else
            report_check "fail" "PySpark not installed in virtual environment"
            if $FIX && ! $CHECK; then
                echo "Info    : Installing PySpark..."
                source "$venv_dir/bin/activate"
                pip install pyspark==3.5.1
                deactivate
            elif $CHECK; then
                echo "Check   : Would install PySpark 3.5.1 in virtual environment"
            fi
            return 1
        fi
    else
        report_check "fail" "Cannot check PySpark - virtual environment missing"
        return 1
    fi
}

# Check if IPython is installed in venv
check_ipython() {
    $DEBUG && echo "Debug   : Checking for IPython installation..."
    
    local venv_dir="${root_dir}/venv"
    
    if [ -d "$venv_dir" ]; then
        if [ -x "$venv_dir/bin/ipython" ]; then
            local ipython_version=$("$venv_dir/bin/ipython" --version 2>/dev/null)
            report_check "pass" "IPython installed in venv: version $ipython_version"
            return 0
        else
            report_check "fail" "IPython not installed in virtual environment"
            if $FIX && ! $CHECK; then
                echo "Info    : Installing IPython..."
                source "$venv_dir/bin/activate"
                pip install ipython
                deactivate
            elif $CHECK; then
                echo "Check   : Would install IPython in virtual environment"
            fi
            return 1
        fi
    else
        report_check "fail" "Cannot check IPython - virtual environment missing"
        return 1
    fi
}

# Check if Java is available (required for PySpark)
check_java() {
    $DEBUG && echo "Debug   : Checking for Java installation..."
    
    if [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
        local java_version=$("$JAVA_HOME/bin/java" -version 2>&1 | head -n 1)
        report_check "pass" "Java found at JAVA_HOME: $java_version"
        return 0
    elif command -v java >/dev/null 2>&1; then
        local java_version=$(java -version 2>&1 | head -n 1)
        report_check "pass" "Java found in PATH: $java_version"
        return 0
    else
        report_check "fail" "Java not found (required for PySpark)"
        if $FIX && ! $CHECK; then
            echo "Info    : Installing OpenJDK 11..."
            sudo apt update
            sudo apt install -y openjdk-11-jdk
        elif $CHECK; then
            echo "Check   : Would install openjdk-11-jdk"
        fi
        return 1
    fi
}

# Check if environment files are generated
check_env_files() {
    $DEBUG && echo "Debug   : Checking for generated environment files..."
    
    local spark_env="${root_dir}/spark/spark_env.sh"
    local ispark_env="${root_dir}/spark/ispark/ispark_env.sh"
    local all_good=true
    
    if [ -f "$spark_env" ]; then
        report_check "pass" "Spark environment file exists: spark/spark_env.sh"
    else
        report_check "fail" "Spark environment file missing: spark/spark_env.sh"
        all_good=false
    fi
    
    if [ -f "$ispark_env" ]; then
        report_check "pass" "iSpark environment file exists: spark/ispark/ispark_env.sh"
    else
        report_check "fail" "iSpark environment file missing: spark/ispark/ispark_env.sh"
        all_good=false
    fi
    
    if [ "$all_good" = false ]; then
        if $FIX && ! $CHECK; then
            echo "Info    : Generating environment files..."
            cd "$root_dir" && python3 linux/generate_env.py spark-client ispark
        elif $CHECK; then
            echo "Check   : Would generate environment files using generate_env.py"
        fi
        return 1
    fi
    
    return 0
}

# Check Spark cluster connectivity
check_spark_connectivity() {
    $DEBUG && echo "Debug   : Checking Spark cluster connectivity..."
    
    local venv_dir="${root_dir}/venv"
    
    # Source environment to get Spark master URL
    if [ -f "${root_dir}/spark/ispark/ispark_env.sh" ]; then
        source "${root_dir}/spark/ispark/ispark_env.sh"
    fi
    
    local spark_master_host=${SPARK_MASTER_EXTERNAL_HOST:-"Lab2.local"}
    local spark_master_port=${SPARK_MASTER_EXTERNAL_PORT:-"32601"}
    
    # Check if master is reachable
    if timeout 2 bash -c "echo >/dev/tcp/$spark_master_host/$spark_master_port" 2>/dev/null; then
        report_check "pass" "Spark master reachable at $spark_master_host:$spark_master_port"
        return 0
    else
        report_check "warn" "Spark master not reachable at $spark_master_host:$spark_master_port"
        report_check "info" "Cluster may be stopped. Start with: cd ansible && ansible-playbook -i inventory.yml playbooks/start.yml"
        return 1
    fi
}

# Check batch application capability
check_batch_apps() {
    $DEBUG && echo "Debug   : Checking batch application capability..."
    
    local apps_dir="${root_dir}/spark/apps"
    
    if [ -d "$apps_dir" ]; then
        local app_count=$(find "$apps_dir" -maxdepth 1 -name "Chapter_*.py" | wc -l)
        if [ $app_count -gt 0 ]; then
            report_check "pass" "Batch applications directory exists with $app_count Chapter_*.py files"
            
            # Check if spark_env.sh is sourced in environment
            if [ -f "${root_dir}/linux/.bashrc" ]; then
                if grep -q "spark_env.sh" "${root_dir}/linux/.bashrc" 2>/dev/null; then
                    report_check "pass" "Spark environment configured in linux/.bashrc"
                else
                    report_check "warn" "Spark environment not configured in linux/.bashrc"
                    report_check "info" "Run: ./linux/link_to_user_env.sh to configure"
                fi
            fi
            return 0
        else
            report_check "warn" "Batch applications directory exists but no Chapter_*.py files found"
            return 1
        fi
    else
        report_check "fail" "Batch applications directory not found: $apps_dir"
        return 1
    fi
}

# Check interactive iPython client capability
check_ipython_client() {
    $DEBUG && echo "Debug   : Checking interactive iPython client..."
    
    local ispark_dir="${root_dir}/spark/ispark"
    local launch_script="${ispark_dir}/launch_ipython.sh"
    local client_script="${ispark_dir}/spark_ipython_client.py"
    local env_file="${ispark_dir}/ispark_env.sh"
    
    local all_good=true
    
    if [ -d "$ispark_dir" ]; then
        report_check "pass" "iSpark directory exists: spark/ispark/"
    else
        report_check "fail" "iSpark directory not found: $ispark_dir"
        return 1
    fi
    
    if [ -x "$launch_script" ]; then
        report_check "pass" "Launch script exists and is executable: launch_ipython.sh"
    else
        report_check "fail" "Launch script missing or not executable: $launch_script"
        all_good=false
        if $FIX && ! $CHECK && [ -f "$launch_script" ]; then
            echo "Info    : Making launch script executable..."
            chmod +x "$launch_script"
        fi
    fi
    
    if [ -f "$env_file" ]; then
        report_check "pass" "Environment file exists: ispark_env.sh"
    else
        report_check "fail" "Environment file not found: $env_file"
        all_good=false
    fi
    
    # Note: spark_ipython_client.py is no longer needed - using standard pyspark
    report_check "info" "Using standard pyspark command (no custom client needed)"
    
    [ "$all_good" = true ] && return 0 || return 1
}

# Check requirements.txt exists for batch apps
check_requirements() {
    $DEBUG && echo "Debug   : Checking for requirements files..."
    
    local req_file="${root_dir}/spark/requirements/requirements.txt"
    
    if [ -f "$req_file" ]; then
        report_check "pass" "Requirements file exists: spark/requirements/requirements.txt"
        
        # Check if requirements are installed in venv
        local venv_dir="${root_dir}/venv"
        if [ -d "$venv_dir" ]; then
            # Simple check - verify a few key packages
            source "$venv_dir/bin/activate"
            if python -c "import pyspark" 2>/dev/null; then
                report_check "pass" "Requirements appear to be installed in venv"
            else
                report_check "warn" "Some requirements may not be installed"
                if $FIX && ! $CHECK; then
                    echo "Info    : Installing requirements..."
                    pip install -r "$req_file"
                elif $CHECK; then
                    echo "Check   : Would install requirements from $req_file"
                fi
            fi
            deactivate 2>/dev/null
        fi
        return 0
    else
        report_check "warn" "Requirements file not found: $req_file"
        return 1
    fi
}

# Test batch application execution (dry-run check)
test_batch_capability() {
    $DEBUG && echo "Debug   : Testing batch application capability..."
    
    local venv_dir="${root_dir}/venv"
    
    if [ ! -d "$venv_dir" ]; then
        report_check "fail" "Cannot test batch apps - virtual environment missing"
        return 1
    fi
    
    # Test if we can import PySpark
    if "$venv_dir/bin/python" -c "import pyspark; from pyspark.sql import SparkSession" 2>/dev/null; then
        report_check "pass" "Batch application capability verified (PySpark imports work)"
        return 0
    else
        report_check "fail" "Batch application capability check failed (PySpark import failed)"
        return 1
    fi
}

# Test interactive client launch script
test_ipython_client() {
    $DEBUG && echo "Debug   : Testing iPython client launch script..."
    
    local launch_script="${root_dir}/spark/ispark/launch_ipython.sh"
    local venv_dir="${root_dir}/venv"
    
    if [ ! -f "$launch_script" ]; then
        report_check "fail" "Cannot test iPython client - launch script not found"
        return 1
    fi
    
    if [ ! -x "$launch_script" ]; then
        report_check "warn" "Launch script exists but is not executable"
        if $FIX && ! $CHECK; then
            chmod +x "$launch_script"
            report_check "info" "Made launch script executable"
        fi
        return 1
    fi
    
    if [ ! -d "$venv_dir" ]; then
        report_check "fail" "Cannot test iPython client - virtual environment missing"
        return 1
    fi
    
    # Test that script syntax is valid
    if bash -n "$launch_script" 2>/dev/null; then
        report_check "pass" "Launch script syntax is valid"
        return 0
    else
        report_check "fail" "Launch script has syntax errors"
        return 1
    fi
}

# Check Spark configuration files
check_spark_config() {
    $DEBUG && echo "Debug   : Checking Spark configuration files..."
    
    local spark_defaults="${root_dir}/spark/conf/spark-defaults.conf"
    local all_good=true
    
    if [ -f "$spark_defaults" ]; then
        report_check "pass" "Spark configuration file exists: spark/conf/spark-defaults.conf"
        
        # Check for critical properties
        if grep -q "spark.master" "$spark_defaults" 2>/dev/null; then
            local master=$(grep "^spark.master" "$spark_defaults" | awk '{print $2}')
            report_check "info" "Spark master configured: $master"
        else
            report_check "warn" "spark.master not configured in spark-defaults.conf"
            all_good=false
        fi
        
        if grep -q "spark.eventLog.enabled" "$spark_defaults" 2>/dev/null; then
            report_check "pass" "Event logging configured in spark-defaults.conf"
        else
            report_check "warn" "Event logging not configured in spark-defaults.conf"
            all_good=false
        fi
    else
        report_check "fail" "Spark configuration file not found: $spark_defaults"
        all_good=false
    fi
    
    [ "$all_good" = true ] && return 0 || return 1
}

# Main execution
echo ""
echo "========================================"
echo " Spark Client Applications Check"
echo "========================================"
echo ""

# Section 1: Python Environment
echo -e "${BLUE}[1/6] Python Environment${NC}"
check_python38
check_venv

echo ""

# Section 2: Spark Dependencies
echo -e "${BLUE}[2/6] Spark Dependencies${NC}"
check_pyspark
check_ipython
check_java

echo ""

# Section 3: Configuration Files
echo -e "${BLUE}[3/6] Configuration Files${NC}"
check_env_files
check_spark_config
check_requirements

echo ""

# Section 4: Batch Applications
echo -e "${BLUE}[4/6] Batch Application Support${NC}"
check_batch_apps
test_batch_capability

echo ""

# Section 5: Interactive Client
echo -e "${BLUE}[5/6] Interactive iPython Client${NC}"
check_ipython_client
test_ipython_client

echo ""

# Section 6: Cluster Connectivity
echo -e "${BLUE}[6/6] Spark Cluster Connectivity${NC}"
check_spark_connectivity

echo ""

# Summary
echo "========================================"
echo " Summary"
echo "========================================"
echo -e "${GREEN}Checks Passed: $CHECKS_PASSED${NC}"
echo -e "${RED}Checks Failed: $CHECKS_FAILED${NC}"

if [ $ISSUES_FOUND -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All checks passed! Spark client applications are ready.${NC}"
    echo ""
    echo "Next Steps:"
    echo "  1. Activate virtual environment: source venv/bin/activate"
    echo "  2. Run batch apps: python spark/apps/Chapter_03.py"
    echo "  3. Launch iPython: ./spark/ispark/launch_ipython.sh"
    echo ""
    exit 0
else
    echo ""
    echo -e "${YELLOW}⚠ Issues found: $ISSUES_FOUND${NC}"
    echo ""
    if $FIX; then
        echo "Some issues were automatically fixed. Rerun this script to verify."
    else
        echo "To automatically fix issues, run with: $script_name --Fix"
    fi
    echo ""
    exit 1
fi

