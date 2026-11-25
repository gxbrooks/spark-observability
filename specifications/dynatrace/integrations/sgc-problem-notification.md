# sgc-problem-notification.json.j2

The brooks-lab Dynatrace problem notification for one ServiceNow instance
(one per `SN_INSTANCES` entry). It posts problems to that instance's OOTB
**SGO-Dynatrace** push connector (`/api/sn_em_connector/em/inbound_event?source=SGO-Dynatrace`).

Variables:

| Variable | Value |
| --- | --- |
| `dt_problem_notification_enabled` | `true` only for the active ServiceNow instance (one brooks-lab notification is enabled at a time) |
| `dt_sn_problem_notification_name` | `SN_INSTANCES[].dt_problem_notification_name` |
| `dt_alerting_profile_object_id` | object id of the brooks-lab alerting profile (`spark-alerting-profile.json.j2`) |
| `sn_dt_event_inbound_url` | the instance's SGO-Dynatrace inbound URL |
| `sn_dt_webhook_authorization` | `Basic …` header for the instance's brooks-lab webhook user (secret) |
| `dt_problem_notification_payload_json` | `sgc-problem-notification-payload.json.j2` rendered, then JSON-encoded as a string (Ansible `to_json`, Terraform `jsonencode()`) |

The payload is a string field that holds JSON, so the caller encodes it; the
template substitutes the encoded string as is.

Dynatrace never returns `secretValue`, so drift checks compare everything
except that field.
