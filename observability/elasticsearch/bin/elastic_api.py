#!/usr/bin/env python3
"""
Unified API client for Elasticsearch and Kibana REST APIs.

This script provides a simplified interface for making HTTP requests to both
Elasticsearch and Kibana services with proper authentication and SSL verification.

Usage:
    elastic_api.py <target> <method> <url_path> [body_path]
    
Arguments:
    target: Either 'elasticsearch' or 'kibana'
    method: HTTP method (GET, POST, PUT, DELETE)
    url_path: API endpoint path (e.g., /_search, /api/data_views/data_view)
    body_path: Optional path to JSON file containing request body

Environment Variables Required:
    For Elasticsearch:
        - ELASTIC_HOST: Elasticsearch hostname
        - ELASTIC_PORT: Elasticsearch port
        - ELASTIC_USER: Username for authentication
        - ELASTIC_PASSWORD: Password for authentication
        - CA_CERT: Path to CA certificate file
    
    For Kibana:
        - KIBANA_HOST: Kibana hostname
        - KIBANA_PORT: Kibana port
        - ELASTIC_USER: Username for authentication (kibana uses elastic user)
        - KIBANA_PASSWORD: Password for authentication
        - CA_CERT: Path to CA certificate file

Examples:
    elastic_api.py elasticsearch GET /_cluster/health
    elastic_api.py kibana POST /api/data_views/data_view dataview.json
    elastic_api.py elasticsearch PUT /_index_template/my-template template.json
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
        "--noauth",
        action="store_true",
        help="Skip authentication (for availability checks)"
    )
    
    args = parser.parse_args()
    
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
    
    return target, method, args.url_path, args.body_path, args.noauth


def get_config(target):
    """Get configuration for the specified target service."""
    config = {}
    
    try:
        config['ca_cert'] = os.environ['CA_CERT']
    except KeyError:
        print("Error: CA_CERT environment variable not set", file=sys.stderr)
        sys.exit(2)
    
    if not os.path.exists(config['ca_cert']):
        print(f"Error: CA certificate path does not exist: {config['ca_cert']}", file=sys.stderr)
        sys.exit(3)
    
    if target == 'elasticsearch':
        try:
            # Prefer _CLIENT version for devops/client contexts, fall back to ELASTIC_HOST
            config['host'] = os.environ.get('ELASTIC_HOST_CLIENT', os.environ.get('ELASTIC_HOST'))
            if not config['host']:
                raise KeyError('ELASTIC_HOST or ELASTIC_HOST_CLIENT')
            config['port'] = os.environ['ELASTIC_PORT']
            config['user'] = os.environ['ELASTIC_USER']
            config['password'] = os.environ['ELASTIC_PASSWORD']
            config['protocol'] = 'https'
        except KeyError as e:
            print(f"Error: Required environment variable not set for Elasticsearch: {e}", file=sys.stderr)
            print("Required: ELASTIC_HOST (or ELASTIC_HOST_CLIENT), ELASTIC_PORT, ELASTIC_USER, ELASTIC_PASSWORD", file=sys.stderr)
            sys.exit(2)
    
    elif target == 'kibana':
        try:
            # Prefer _CLIENT version for devops/client contexts, fall back to KIBANA_HOST
            config['host'] = os.environ.get('KIBANA_HOST_CLIENT', os.environ.get('KIBANA_HOST'))
            if not config['host']:
                raise KeyError('KIBANA_HOST or KIBANA_HOST_CLIENT')
            config['port'] = os.environ['KIBANA_PORT']
            config['user'] = os.environ['ELASTIC_USER']
            config['password'] = os.environ['KIBANA_PASSWORD']
            config['protocol'] = 'http'  # TODO: Enable TLS encryption on Kibana
        except KeyError as e:
            print(f"Error: Required environment variable not set for Kibana: {e}", file=sys.stderr)
            print("Required: KIBANA_HOST (or KIBANA_HOST_CLIENT), KIBANA_PORT, ELASTIC_USER, KIBANA_PASSWORD", file=sys.stderr)
            sys.exit(2)
    
    return config


def make_api_request(config, method, url_path, body_path=None, noauth=False):
    """Make the HTTP request to the API endpoint."""
    url = f"{config['protocol']}://{config['host']}:{config['port']}{url_path}"
    
    headers = {
        "kbn-xsrf": "true",
        "Content-Type": "application/json"
    }
    
    # Load request body if provided
    body = None
    if body_path:
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
        
        # For noauth mode (availability checks), any HTTP response means service is up
        if noauth:
            # 401/403 are expected without auth - service is responding
            if response.status_code in (200, 401, 403):
                return response.status_code, {}
            # For other codes, still try to get JSON
            try:
                return response.status_code, response.json()
            except:
                return response.status_code, {}
        
        # Normal mode: Raise exception for HTTP errors
        response.raise_for_status()
        
        # Return the JSON response
        return response.status_code, response.json()
    
    except requests.exceptions.HTTPError as e:
        # HTTP error occurred (4xx or 5xx)
        status_code = e.response.status_code if e.response else None
        try:
            error_data = e.response.json() if e.response else None
            print(f"HTTP {status_code} Error: {e}", file=sys.stderr)
            if error_data:
                print(json.dumps(error_data, indent=2))
            return status_code, error_data
        except:
            print(f"HTTP Error: {e}", file=sys.stderr)
            if e.response:
                print(f"Response text: {e.response.text}", file=sys.stderr)
            return None, None
    
    except requests.exceptions.RequestException as e:
        # Network or connection error
        print(f"Request failed: {e}", file=sys.stderr)
        return None, None
    
    except Exception as e:
        # Unexpected error
        print(f"Unexpected error: {e}", file=sys.stderr)
        return None, None


def main():
    """Main entry point."""
    target, method, url_path, body_path, noauth = parse_arguments()
    
    if DEBUG:
        print(f"Target: {target}, Method: {method}, Path: {url_path}", file=sys.stderr)
    
    config = get_config(target)
    status, response = make_api_request(config, method, url_path, body_path, noauth)
    
    if status is None:
        # Error already printed to stderr
        sys.exit(3)
    elif response is None:
        print(f"Warning: No response body with status {status}", file=sys.stderr)
        sys.exit(0)
    elif noauth and status in (200, 401, 403):
        # For availability checks, 401/403 means service is responding (success)
        sys.exit(0)
    elif status == 200:
        # Success - print formatted JSON
        print(json.dumps(response, indent=2))
        sys.exit(0)
    else:
        # Non-200 status - print response and exit with warning
        print(f"Warning: Non-200 status code: {status}", file=sys.stderr)
        print(json.dumps(response, indent=2))
        sys.exit(0)


if __name__ == "__main__":
    main()

