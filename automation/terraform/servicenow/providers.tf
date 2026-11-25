terraform {
  required_version = ">= 1.9"

  required_providers {
    # Generic REST provider over the ServiceNow Table API (project decision: community/generic
    # providers before any custom provider). Table API responses wrap records in {"result": ...};
    # resources use read_search with results_key = "result" to unwrap them.
    restapi = {
      source  = "Mastercard/restapi"
      version = "~> 3.0"
    }
  }
}

provider "restapi" {
  uri                   = var.SN_URL
  username              = var.SN_USER
  password              = var.SN_PASSWORD
  id_attribute          = "result/sys_id"
  create_returns_object = true
  write_returns_object  = true
  update_method         = "PATCH"
  headers = {
    Accept       = "application/json"
    Content-Type = "application/json"
  }
}
