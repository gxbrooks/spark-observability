import argparse
import sys
import os.path
import os

def parse_args(): 

    # Create an ArgumentParser object
    parser = argparse.ArgumentParser(description="Process API calls to Kibana")

    # Add arguments
    parser.add_argument("method", help="The HTTP method used to call the API (GET, PUT, or POST)")
    parser.add_argument("url_path", help="The URL path (without the hostname or port) of the API call.")
    parser.add_argument("body_path", nargs="?", help="An optional file that contains a JSON structure for the API call")

    # Parse the arguments
    args = parser.parse_args()

    method = args.method.upper()
    url_path=args.url_path
    body_path = args.body_path

    if method not in ("PUT", "GET", "POST"):
        print(f"method ({method}) must be one of GET, POST, OR PUT")
        sys.exit(1)

    if method == "PUT":
        if body_path == None:
            print(f"PUT methods should have a body file specified")
            # But not in some cases like: PUT /batch-events-000001 
            # sys.exit(1)
        elif not os.path.isfile(body_path):
            print(f"{body_path} does not exist or is not a file")
            sys.exit(1)
    elif body_path == None:
        # for GET and POST bodies are optional - even GETs
        pass

    return (method, url_path, body_path)
