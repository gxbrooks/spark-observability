# sgc-api-token.json.j2

Dynatrace access token (`POST /api/v2/apiTokens`) the ServiceNow Service Graph
Connector uses to read topology. `${dt_sgc_api_token_name}` is per ServiceNow
instance (`SN_INSTANCES[].dt_sgc_api_token_name` in `vars/variables.yaml`), so
two instances never share or rotate each other's token.

The file holds only the token definition. The token value exists only in the
API response; the deploy task
(`automation/ansible/playbooks/servicenow/sgc/sources/dynatrace/tasks/ensure-sgc-credential.yml`)
pushes it straight into the ServiceNow *Dynatrace API Key* credential and never
writes it to a file. Token values cannot be read back, so the task mints only
when the token is missing or a rotation is requested; it does not compare the
scopes of an existing token.
