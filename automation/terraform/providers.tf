terraform {
  required_version = ">= 1.9"

  required_providers {
    dynatrace = {
      source  = "dynatrace-oss/dynatrace"
      version = "~> 1.106"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    elasticstack = {
      source  = "elastic/elasticstack"
      version = "~> 0.16"
    }
  }
}

provider "dynatrace" {
  dt_env_url   = var.DT_API_URL
  dt_api_token = var.DT_API_TOKEN
}

# All three K8s-facing providers point at the same kubeconfig -- the
# control-plane host's admin config, same one Ansible's kubeconfig tasks
# in k8s/install.yml produce, copied locally to this control node.
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

# hashicorp/kubernetes's own kubernetes_manifest resource needs the CRD
# already queryable in its provider schema at plan time -- a problem when
# the CRD is installed by the helm_release in the very same apply
# (DynaKube's CRD, via the operator chart's installCRD=true). kubectl_manifest
# (community, very widely used for exactly this) applies raw YAML without
# that constraint, so it's what manages the DynaKube CR here.
provider "kubectl" {
  config_path = var.kubeconfig_path
}

# Elasticsearch/Kibana credentials come in via vars/contexts/elastic_terraform.auto.tfvars.json
# (the "elastic-terraform" context -- same generate-contexts pattern as Dynatrace).
# TLS is self-signed in this lab (same cert chain esapi/kapi already skip-verify on),
# so insecure = true here mirrors deploy.yml's validate_certs: false Elasticsearch probe.
provider "elasticstack" {
  elasticsearch {
    endpoints = [var.ES_URL]
    username  = var.ES_USER
    password  = var.ES_PASSWORD
    insecure  = true
  }
  kibana {
    # Kibana itself serves plain HTTP in this lab (no server.ssl.* config;
    # see specifications/docker-compose.yml's kibana service) -- only
    # Elasticsearch terminates TLS.
    endpoints = ["http://${var.KB_HOST}:${var.KB_PORT}"]
    username  = var.ES_USER
    password  = var.ES_PASSWORD
  }
}
