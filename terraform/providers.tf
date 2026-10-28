terraform {
  required_version = ">= 1.9"

  required_providers {
    dynatrace = {
      source  = "dynatrace-oss/dynatrace"
      version = "~> 1.106"
    }
  }
}

provider "dynatrace" {
  dt_env_url   = var.DT_API_URL
  dt_api_token = var.DT_API_TOKEN
}
