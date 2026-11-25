# Shared state with locking (automation standard, Terraform statement 1).
# The state lives in the brooks-lab cluster as Secret
# tfstate-default-spark-observability (namespace default); Terraform locks it
# with a coordination.k8s.io Lease of the same name for every plan/apply, so
# two runs can't write it at once. Anyone with the cluster's admin kubeconfig
# (the same one the kubernetes/helm/kubectl providers use) shares this state.
# The state holds secrets (Dynakube token, API tokens): read access to Secrets
# in namespace default is read access to them.
# Backend blocks can't use variables, so the kubeconfig path is fixed here;
# override per machine with: terraform init -backend-config="config_path=<path>"
terraform {
  backend "kubernetes" {
    secret_suffix = "spark-observability"
    namespace     = "default"
    config_path   = "~/.kube/config"
  }
}
