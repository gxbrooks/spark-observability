#!/usr/bin/env python3
"""
Unified API client for Elasticsearch and Kibana REST APIs.

This script provides a simplified interface for making HTTP requests to both
Elasticsearch and Kibana services with proper authentication and SSL verification.

Usage:
    elastic_api.py <target> <method> <url_path> [body_path]
    elastic_api.py <target> <method> <url_path> -d <json_data>
    
Arguments:
    target: Either 'elasticsearch' or 'kibana'
    method: HTTP method (GET, POST, PUT, DELETE)
    url_path: API endpoint path (e.g., /_search, /api/data_views/data_view)
    body_path: Optional path to JSON file containing request body

Flags:
    -d, --data: Inline JSON data (alternative to body_path, curl-style)
    --noauth: Skip authentication (for availability checks)
    --allow-errors: Allow 4xx errors without failing (for conditional logic)

Exit Codes:
    0: Success
       - HTTP 200 response, OR
       - HTTP 401/403 with --noauth flag (service is responding)
    
    1: Expected HTTP error (with --allow-errors flag)
       - HTTP 4xx client errors (400-499)
       - Response body printed to stdout for conditional processing
    
    2: Unexpected HTTP error
       - HTTP 5xx server errors (500-599)
       - Other unexpected HTTP errors
    
    3: System failure
       - Network error, connection refused, timeout
       - No HTTP response received

Environment Variables Required:
    For Elasticsearch (ES_* prefix, ES already stands for Elasticsearch):
        - ES_HOST: Elasticsearch hostname
        - ES_PORT: Elasticsearch port
        - ES_USER: Username for authentication
        - ES_PASSWORD: Password for authentication
        - CA_CERT_ES_PATH: Path to CA certificate file (or CA_CERT for backward compatibility)
    
    For Kibana (KB_* prefix, no ES_ prefix needed):
        - KB_HOST: Kibana hostname
        - KB_PORT: Kibana port
        - ES_USER: Username for authentication
        - KB_PASSWORD: Password for authentication
        - CA_CERT_ES_PATH: Path to CA certificate file (or CA_CERT for backward compatibility)

Examples:
    # Basic usage with file
    elastic_api.py elasticsearch GET /_cluster/health
    elastic_api.py kibana POST /api/data_views/data_view dataview.json
    
    # Using inline data (curl-style)
    elastic_api.py elasticsearch POST /batch-events/_count -d '{"query": {"match_all": {}}}'
    elastic_api.py elasticsearch POST /index/_search --data '{"size": 10}'
    
    # Availability check (allows 401/403 as success)
    elastic_api.py --noauth elasticsearch GET /
    
    # Conditional check (test if resource exists)
    if elastic_api.py --allow-errors elasticsearch GET /_transform/my-transform; then
        echo "Transform exists"
    else
        echo "Transform does not exist (got error code $?)"
    fi
"""

import argparse
import sys
import os
import json
import requests

DEBUG = os.environ.get('API_DEBUG', 'false').lower() == 'true'


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Unified API client for Elasticsearch and Kibana",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    parser.add_argument(
        "target",
        choices=["elasticsearch", "kibana", "es", "kb"],
        help="Target service (elasticsearch/es or kibana/kb)"
    )
    parser.add_argument(
        "method",
        help="HTTP method (GET, POST, PUT, DELETE)"
    )
    parser.add_argument(
        "url_path",
        help="API endpoint path (e.g., /_search, /api/data_views/data_view)"
    )
    parser.add_argument(
        "body_path",
        nargs="?",
        help="Optional path to JSON file containing request body"
    )
    parser.add_argument(
        "-d", "--data",
        dest="inline_data",
        help="Inline JSON data (alternative to body_path, curl-style)"
    )
    parser.add_argument(
        "--noauth",
        action="store_true",
        help="Skip authentication (for availability checks)"
    )
    parser.add_argument(
        "--allow-errors",
        action="store_true",
        help="Allow 4xx errors without failing (exit code 1, for conditional logic)"
    )
    
    args = parser.parse_args()
    
    # Validate that body_path and inline_data are mutually exclusive
    if args.body_path and args.inline_data:
        print("Error: Cannot specify both body_path and -d/--data flags", file=sys.stderr)
        sys.exit(1)
    
    # Normalize target
    target = args.target.lower()
    if target in ('es', 'elasticsearch'):
        target = 'elasticsearch'
    elif target in ('kb', 'kibana'):
        target = 'kibana'
    
    # Normalize method
    method = args.method.upper()
    if method not in ('GET', 'POST', 'PUT', 'DELETE'):
        print(f"Error: Invalid HTTP method '{method}'. Must be GET, POST, PUT, or DELETE", file=sys.stderr)
        sys.exit(1)
    
    # Validate body_path if provided
    if args.body_path:
        if not os.path.isfile(args.body_path):
            print(f"Error: Body file '{args.body_path}' does not exist or is not a file", file=sys.stderr)
            sys.exit(1)
    
    return target, method, args.url_path, args.body_path, args.inline_data, args.noauth, args.allow_errors


def get_config(target):
    """Get configuration for the specified target service."""
    config = {}
    
    # Prefer CA_CERT_ES_PATH (standardized), fall back to ES_CA_CERT or CA_CERT (backward compatibility)
    config['ca_cert'] = os.environ.get('CA_CERT_ES_PATH', os.environ.get('ES_CA_CERT', os.environ.get('CA_CERT')))
    if not config['ca_cert']:
        print("Error: CA_CERT_ES_PATH, ES_CA_CERT, or CA_CERT environment variable not set", file=sys.stderr)
        sys.exit(2)
    
    if not os.path.exists(config['ca_cert']):
        print(f"Error: CA certificate path does not exist: {config['ca_cert']}", file=sys.stderr)
        sys.exit(3)
    
    if target == 'elasticsearch':
        try:
            # Use ES_* variables (standardized, ES already stands for Elasticsearch)
            config['host'] = os.environ.get('ES_HOST')
            if not config['host']:
                raise KeyError('ES_HOST')
            config['port'] = os.environ.get('ES_PORT')
            if not config['port']:
                raise KeyError('ES_PORT')
            config['user'] = os.environ.get('ES_USER')
            if not config['user']:
                raise KeyError('ES_USER')
            config['password'] = os.environ.get('ES_PASSWORD')
            if not config['password']:
                raise KeyError('ES_PASSWORD')
            config['protocol'] = 'https'
        except KeyError as e:
            print(f"Error: Required environment variable not set for Elasticsearch: {e}", file=sys.stderr)
            print("Required: ES_HOST, ES_PORT, ES_USER, ES_PASSWORD", file=sys.stderr)
            sys.exit(2)
    
    elif target == 'kibana':
        try:
            # Use KB_* variables (no ES_ prefix needed for Kibana)
            config['host'] = os.environ.get('KB_HOST')
            if not config['host']:
                raise KeyError('KB_HOST')
            config['port'] = os.environ.get('KB_PORT')
            if not config['port']:
                raise KeyError('KB_PORT')
            config['user'] = os.environ.get('ES_USER')
            if not config['user']:
                raise KeyError('ES_USER')
            config['password'] = os.environ.get('KB_PASSWORD')
            if not config['password']:
                raise KeyError('KB_PASSWORD')
            config['protocol'] = 'http'  # TODO: Enable TLS encryption on Kibana
        except KeyError as e:
            print(f"Error: Required environment variable not set for Kibana: {e}", file=sys.stderr)
            print("Required: KB_HOST, KB_PORT, ES_USER, KB_PASSWORD", file=sys.stderr)
            sys.exit(2)
    
    return config


def make_api_request(config, method, url_path, body_path=None, inline_data=None, noauth=False, allow_errors=False):
    """
    Make the HTTP request to the API endpoint.
    
    Returns:
        tuple: (status_code, response_data)
        - status_code: HTTP status code (int) or None if system failure
        - response_data: Parsed JSON response (dict) or None
    """
    url = f"{config['protocol']}://{config['host']}:{config['port']}{url_path}"
    
    headers = {
        "kbn-xsrf": "true",
        "Content-Type": "application/json"
    }
    
    # Load request body from inline data or file
    body = None
    if inline_data:
        try:
            body = json.loads(inline_data)
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON in inline data: {e}", file=sys.stderr)
            sys.exit(4)
    elif body_path:
        try:
            with open(body_path, 'r') as f:
                body = json.load(f)
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON in body file: {e}", file=sys.stderr)
            sys.exit(4)
        except Exception as e:
            print(f"Error: Failed to read body file: {e}", file=sys.stderr)
            sys.exit(4)
    
    if DEBUG:
        print(f"Request: {method} {url}", file=sys.stderr)
        if body_path:
            print(f"Body file: {body_path}", file=sys.stderr)
        if noauth:
            print(f"No authentication (availability check mode)", file=sys.stderr)
        if allow_errors:
            print(f"Allow errors mode (4xx will exit with code 1)", file=sys.stderr)
    
    # Make the request
    try:
        auth = None if noauth else (config['user'], config['password'])
        
        if method == 'GET':
            response = requests.get(url, auth=auth, headers=headers, json=body, verify=config['ca_cert'])
        elif method == 'POST':
            response = requests.post(url, auth=auth, headers=headers, json=body, verify=config['ca_cert'])
        elif method == 'PUT':
            response = requests.put(url, auth=auth, headers=headers, json=body, verify=config['ca_cert'])
        elif method == 'DELETE':
            response = requests.delete(url, auth=auth, headers=headers, verify=config['ca_cert'])
        else:
            print(f"Error: Unsupported HTTP method: {method}", file=sys.stderr)
            sys.exit(1)
        
        if DEBUG:
            print(f"Response: HTTP {response.status_code}", file=sys.stderr)
        
        # Try to get JSON response
        try:
            response_data = response.json()
        except:
            response_data = {"text": response.text} if response.text else {}
        
        # Return status and data for caller to handle
        return response.status_code, response_data
    
    except requests.exceptions.RequestException as e:
        # Network or connection error - system failure
        print(f"Request failed: {e}", file=sys.stderr)
        return None, None
    
    except Exception as e:
        # Unexpected error - system failure
        print(f"Unexpected error: {e}", file=sys.stderr)
        return None, None


def main():
    """
    Main entry point.
    
    Exit Codes:
        0: Success (HTTP 200, or 401/403 with --noauth)
        1: Expected HTTP error (4xx with --allow-errors)
        2: Unexpected HTTP error (5xx or other errors)
        3: System failure (no response)
    """
    target, method, url_path, body_path, inline_data, noauth, allow_errors = parse_arguments()
    
    if DEBUG:
        print(f"Target: {target}, Method: {method}, Path: {url_path}", file=sys.stderr)
        print(f"Flags: noauth={noauth}, allow_errors={allow_errors}", file=sys.stderr)
    
    config = get_config(target)
    status, response = make_api_request(config, method, url_path, body_path, inline_data, noauth, allow_errors)
    
    # Exit code 3: System failure (no HTTP response)
    if status is None:
        print(f"Error: System failure - no HTTP response received", file=sys.stderr)
        sys.exit(3)
    
    # Print response body to stdout (except for conditional checks or pure noauth)
    # For conditional checks with --allow-errors, only print on errors
    if noauth and status in (200, 401, 403):
        # Pure availability check - no output
        pass
    elif allow_errors and status < 400:
        # Conditional check succeeded - no output needed
        pass
    elif allow_errors and status >= 400:
        # Conditional check failed - print error for diagnostics
        if response:
            print(json.dumps(response, indent=2))
        else:
            print(f"{{\"error\": \"HTTP {status} with no response body\"}}")
    else:
        # Normal mode - always print response
        if response:
            print(json.dumps(response, indent=2))
        elif status >= 400:
            print(f"{{\"error\": \"HTTP {status} with no response body\"}}")
    
    # Exit code 0: Success
    if status == 200:
        sys.exit(0)
    
    # Exit code 0: Availability check success (noauth mode)
    if noauth and status in (200, 401, 403):
        sys.exit(0)
    
    # Exit code 1: Expected HTTP error (4xx with allow-errors)
    if allow_errors and 400 <= status < 500:
        if DEBUG:
            print(f"Expected error: HTTP {status} (exit 1)", file=sys.stderr)
        sys.exit(1)
    
    # Exit code 2: Unexpected HTTP error (5xx or any error without allow-errors)
    if status >= 400:
        if not allow_errors:
            # Print error message to stderr for unexpected errors
            print(f"Error: HTTP {status} - {method} {url_path}", file=sys.stderr)
        if DEBUG:
            print(f"Unexpected error: HTTP {status} (exit 2)", file=sys.stderr)
        sys.exit(2)
    
    # Exit code 0: Other 2xx/3xx success codes
    sys.exit(0)


if __name__ == "__main__":
    main()

