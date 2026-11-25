# sys_ws_definition_sm_operations_api.json

Scripted REST API (`sys_ws_definition`) that exposes the Service Mapping
operations Ansible calls. Its resources (`sys_ws_operation`) are:

| Representation | Script |
|---|---|
| `sys_ws_operation_sm_discover.json` | `sm_discover_service.js` |
| `sys_ws_operation_sm_populate_tags.json` | `sm_populate_tag_list.js` |
| `sys_ws_operation_sm_ensure_tag_categories.json` | `sm_ensure_tag_categories.js` |

The deploy task
(`automation/ansible/playbooks/servicenow/service-mapping/tasks/deploy-sm-rest-api.yml`)
adds two fields to each operation at apply time, so they are not in the
operation files:

- `web_service_definition`: sys_id of this API on the target instance (looked up, or created).
- `operation_script`: the contents of the script file listed above (the source file is the
  representation of the script).

The API `name` is the lookup key; an operation is matched by parent API,
`http_method` and `relative_path`.
