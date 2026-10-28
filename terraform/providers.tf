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
  dt_env_url   = var.dt_api_url
  dt_api_token = var.dt_api_token
}
