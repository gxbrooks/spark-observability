
import os
import sys
import json

import args
import api

def main(): 

    (method, url_path, body_path) = args.parse_args()

    port = None
    password = None
    user = None
    host = None
    ca_cert_path = None

    # should use:
    #   if "VARIABLE" in os.environ:
    #      var = os.environ["VARIABLE"] 
    #   else:
    #       print(f"KIBANA_PORT ({port}) or KIBANA_PASSWORD not defined in the environment")
    #       sys.exit(2)
    try:
        ca_cert_path = os.environ["CA_CERT"]
        user = os.environ["ELASTIC_USER"]
        host = os.environ["KIBANA_HOST"]
        password = os.environ["KIBANA_PASSWORD"]
        port = os.environ["KIBANA_PORT"]
    except: 
        print(f"KIBANA_PORT ({port}) or KIBANA_PASSWORD not defined in the environment")
        sys.exit(2)

    # TODO: Enable TLS encryption on Kibana
    url = "http://" + host + ":" + port + url_path

    if not os.path.exists(ca_cert_path):
        print(f"Root CA path does not exist ({ca_cert_path})", file=sys.stderr)
        sys.exit(3)

    headers = {
        "kbn-xsrf": "true",  # Replace with a real XSRF token
        "Content-Type": "application/json"
    }
    (status, response) = api.api_request(method, url, user, password, headers, ca_cert_path, body_file=body_path)

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


