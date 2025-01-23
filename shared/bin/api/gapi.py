
import os
import sys
import json

import args
import docker
import api

# NOT Debugged!!

def main(): 

    (method, url_path, body_path) = args.parse_args()

    port = None
    user = None
    password = None
    url_prefix = None

    try:
        port = os.environ["ELASTIC_PORT"]
        password = os.environ["GF_SECURITY_ADMIN_PASSWORD"]
        user = os.environ["GF_SECURITY_ADMIN_USER"]
        url_prefix = os.environ["ELASTIC_URL"]
    except: 
        print(f"ELASTIC_PORT ({port}), ELASTIC_USER ({user}), ELASTIC_URL ({url_prefix}) or ELASTIC_PASSWORD not defined in the environment")
        sys.exit(2)


    url = "https://" + host + ":" + port + url_path
    ca_cert_path = os.environ["CA_CERT"]

    headers = {
        "kbn-xsrf": "true",  # Replace with a real XSRF token
        "Content-Type": "application/json"
    }
    (status, response) = api.api_request(method, url, "elastic", password, headers, ca_cert_path, body_file=body_path)

    if status == None:
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


