
import os
import sys
import json

import args
import docker
import api

def main(): 

    (method, url_path, body_path) = args.parse_args()

    port = None
    user = None
    password = None
    host = None

    try:
        ca_cert_path = os.environ["CA_CERT"]
        host = os.environ["ELASTIC_HOST"]
        password = os.environ["ELASTIC_PASSWORD"]
        port = os.environ["ELASTIC_PORT"]
        user = os.environ["ELASTIC_USER"]
    except: 
        print(f"ELASTIC_PORT ({port}), ELASTIC_USER ({user}), ELASTIC_HOST ({host}) or ELASTIC_PASSWORD not defined in the environment", 
            file=sys.stderr)
        sys.exit(2)

    url = "https://" + host + ":" + port + url_path

    if not os.path.exists(ca_cert_path):
        print(f"Root CA path does not exist ({ca_cert_path})", file=sys.stderr)
        sys.exit(3)

    headers = {
        "kbn-xsrf": "true",  # Replace with a real XSRF token
        "Content-Type": "application/json"
    }
    (status, response) = api.api_request(method, url, "elastic", password, headers, ca_cert_path, body_file=body_path)

    if status == None:
        print(f"No HTTP status for method={method} url={url}", file=sys.stderr)
        sys.exit(3)
    elif response == None:
        print(f"Result is None with status={status}", file=sys.stderr)
    elif status == 200:
        print(json.dumps(response, indent=2)) 
    else:
        print(f"Non-200 status ({status}) is suspect with response = {response}", file=sys.stderr)
        print(json.dumps(response, indent=2))

if __name__ == "__main__":
    main()


