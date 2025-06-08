#!/usr/bin/env python3
"""
This script reads an env.conf file (systemd drop-in format) and generates a semicolon-separated string
suitable for use as the value of the 'Environment' property for a Windows service via Set-ItemProperty.

Usage:
    python3 envconf_to_win_env.py /path/to/env.conf
"""
import sys
import re

if len(sys.argv) != 2:
    print("Usage: python3 envconf_to_win_env.py /path/to/env.conf")
    sys.exit(1)

conf_path = sys.argv[1]

env_vars = []
with open(conf_path, 'r') as f:
    for line in f:
        line = line.strip()
        # Match lines like: Environment="KEY=VALUE"
        m = re.match(r'Environment="([A-Za-z0-9_]+)=(.*)"', line)
        if m:
            key, value = m.groups()
            # Escape any embedded semicolons
            value = value.replace(';', '\;')
            env_vars.append(f"{key}={value}")

# Join with semicolons
print(';'.join(env_vars))
