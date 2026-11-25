# RabbitMQ discovery configuration: the RabbitMQ-API discovery source the IRE runs of
# automation/ansible/playbooks/servicenow/discovery/rabbitmq/start.yml are attributed to.
# Same representation file Ansible's deploy.yml applies. The discovery run itself is procedural
# (read the broker, reconcile through the IRE) and stays in Ansible.

locals {
  sn_rabbitmq_dir = "${path.module}/../../../specifications/servicenow/integrations/discovery/rabbitmq"
  rabbitmq_choice = jsondecode(file("${local.sn_rabbitmq_dir}/sys_choice_discovery_source_rabbitmq_api.json"))
}

resource "restapi_object" "discovery_source_rabbitmq_api" {
  path = "/api/now/table/sys_choice"
  data = jsonencode(local.rabbitmq_choice)

  read_search = {
    results_key  = "result"
    search_key   = "sys_id"
    search_value = "{id}"
    query_string = "sysparm_query=name=${local.rabbitmq_choice.name}^element=${local.rabbitmq_choice.element}^value=${local.rabbitmq_choice.value}"
  }

  # The Table API returns every column; only the representation's fields are managed.
  ignore_server_additions = true
}
