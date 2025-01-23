
import sys
import os
import json
import ssl
import requests

debug = True

def api_request(http_method, url, username, password, headers, ca_cert_path, body_file=None):
    """Makes an API request with basic authentication, custom headers, an optional body, and optional CA certificate verification.

    Args:
        url: The API endpoint URL.
        username: The username for basic authentication.
        password: The password for basic authentication.
        headers: A dictionary of headers.
        ca_cert_path: Path to the CA certificate file 
        body_file: Path to the JSON body file (optional).

    Returns:
        The status of the request and a the JSON object (dictionary) representing the API response, or (None, None) 
        if a system-level or http-level error occurs. HTTP level errors include HTTP 400 and 500 status codes. If
        api_request detects an error, it wiil send an error message to stderr and return (None, None). Some API calls 
        may not successfully complete returnning an HTTP status and JSON structure with error information embedded in 
        the JSON structure. The caller will need assess if such responses represent a fatal error or not.
        
    """
    if not os.path.exists(ca_cert_path):
        print(f"Root certificate ({ca_cert_path}) does not exist")
        sys.exit(3)
    if debug:
        print(f"API: http_method={http_method}\n     url={url}\n     body={body_file}", file=sys.stderr)
    try:
        if body_file:
            if os.path.exists(body_file):
                with open(body_file, "r") as f:
                    try:
                        body = json.load(f)  # Load JSON from file
                    except json.JSONDecodeError as e:
                        print(f"Error decoding JSON body from file: {e}", file=sys.stderr)
                        return (None, None)
            else:
                print(f"Body file ({body_file}) does not exist", file=sys.stderr)
                return (None, None)
        else:
            body = None

        if http_method == "PUT":
            response = requests.put(url, auth=(username, password), headers=headers, json=body, verify=ca_cert_path)
        elif http_method == "POST":
            response = requests.post(url, auth=(username, password), headers=headers, json=body, verify=ca_cert_path)
        elif http_method == "GET":
            response = requests.get(url, auth=(username, password), headers=headers, json=body, verify=ca_cert_path)
        else:
            print(f"Bad method = {http_method}", file=sys.stderr)
            return (None, None)


        if debug:
            print(f"API: Returned HTTP {response.status_code} for url={url}\n     body={body_file}", file=sys.stderr)
                
        response.raise_for_status()  # Raise an exception for bad status codes (4xx or 5xx)

        return (response.status_code, response.json())

    # would prefer to return status codes, but that takes a little investigation
    except requests.exceptions.RequestException as e:
        print(f"API request failed: {e}", file=sys.stderr)
        if hasattr(e.response, 'text'):
          print(f"Response text: {e.response.text}", file=sys.stderr)
        return (None, None)
    except OSError as e:
        print(f"File error: {e}", file=sys.stderr)
        return (None, None)
    except Exception as e:
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        return (None, None)

