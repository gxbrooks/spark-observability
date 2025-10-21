#!/bin/bash

# Verify ID Consistency Across Hosts
# 
# This script checks that critical UIDs and GIDs are consistent across
# all managed hosts in the environment.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

# Load standard IDs
source "$script_dir/standard_ids.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================"
echo "UID/GID Consistency Verification"
echo "============================================"
echo ""

# Function to check user/group on a host
check_host() {
    local host=$1
    echo "Checking $host..."
    
    # Check spark group
    SPARK_GID_ACTUAL=$(ansible $host -i "$root_dir/ansible/inventory.yml" -m shell -a "getent group spark | cut -d: -f3" 2>/dev/null | grep -v "CHANGED" | grep -v "rc=0" | tail -1 | tr -d ' ')
    
    if [[ "$SPARK_GID_ACTUAL" == "$SPARK_GID" ]]; then
        echo -e "  ${GREEN}✓${NC} spark GID: $SPARK_GID_ACTUAL (correct)"
    else
        echo -e "  ${RED}✗${NC} spark GID: $SPARK_GID_ACTUAL (expected $SPARK_GID)"
        ERRORS=1
    fi
    
    # Check ansible user
    ANSIBLE_UID_ACTUAL=$(ansible $host -i "$root_dir/ansible/inventory.yml" -m shell -a "id -u ansible 2>/dev/null || echo 'MISSING'" 2>/dev/null | grep -v "CHANGED" | grep -v "rc=0" | tail -1 | tr -d ' ')
    ANSIBLE_GID_ACTUAL=$(ansible $host -i "$root_dir/ansible/inventory.yml" -m shell -a "id -g ansible 2>/dev/null || echo 'MISSING'" 2>/dev/null | grep -v "CHANGED" | grep -v "rc=0" | tail -1 | tr -d ' ')
    
    if [[ "$ANSIBLE_UID_ACTUAL" == "MISSING" ]]; then
        echo -e "  ${YELLOW}!${NC} ansible user: NOT FOUND"
    elif [[ "$ANSIBLE_UID_ACTUAL" == "$ANSIBLE_UID" ]]; then
        echo -e "  ${GREEN}✓${NC} ansible UID: $ANSIBLE_UID_ACTUAL (correct)"
    else
        echo -e "  ${YELLOW}!${NC} ansible UID: $ANSIBLE_UID_ACTUAL (expected $ANSIBLE_UID, but may vary)"
    fi
    
    if [[ "$ANSIBLE_GID_ACTUAL" != "MISSING" ]]; then
        if [[ "$ANSIBLE_GID_ACTUAL" == "$ANSIBLE_GID" ]]; then
            echo -e "  ${GREEN}✓${NC} ansible GID: $ANSIBLE_GID_ACTUAL (correct)"
        else
            echo -e "  ${YELLOW}!${NC} ansible GID: $ANSIBLE_GID_ACTUAL (expected $ANSIBLE_GID, but may vary)"
        fi
    fi
    
    # Check elastic-agent membership in spark group
    EA_IN_SPARK=$(ansible $host -i "$root_dir/ansible/inventory.yml" -m shell -a "groups elastic-agent 2>/dev/null | grep -o spark" 2>/dev/null | grep -v "CHANGED" | grep -v "rc=0" | tail -1 | tr -d ' ')
    
    if [[ "$EA_IN_SPARK" == "spark" ]]; then
        echo -e "  ${GREEN}✓${NC} elastic-agent in spark group"
    else
        echo -e "  ${RED}✗${NC} elastic-agent NOT in spark group"
        ERRORS=1
    fi
    
    echo ""
}

ERRORS=0

# Get list of hosts from inventory
HOSTS=$(ansible all -i "$root_dir/ansible/inventory.yml" --list-hosts 2>/dev/null | grep -v "hosts (" | tr -d ' ')

for host in $HOSTS; do
    check_host "$host"
done

echo "============================================"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✓ All critical IDs are consistent${NC}"
    echo ""
    echo "Standard IDs:"
    echo "  - spark: UID=$SPARK_UID, GID=$SPARK_GID"
    echo "  - ansible: UID=$ANSIBLE_UID, GID=$ANSIBLE_GID"
else
    echo -e "${RED}✗ ID inconsistencies detected${NC}"
    echo ""
    echo "To fix, run the appropriate assert_* scripts on each host:"
    echo "  - ./linux/assert_spark_user.sh"
    echo "  - ./linux/assert_managed_node.sh --User ansible --Password <pwd>"
    exit 1
fi
echo "============================================"

