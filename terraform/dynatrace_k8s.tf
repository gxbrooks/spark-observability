# Dynatrace Operator (Helm) + the Dynakube token Secret + the DynaKube CR
# itself. Mirrors ansible/playbooks/observability/dynatrace/tasks/deploy_operator.yml
# and apply_dynakube.yml -- same Helm chart/repo, same secret shape, same
# dynakube.yaml.j2 template file (Phase 1's shared representation, read
# here via templatefile() exactly like the Settings objects in
# dynatrace_settings.tf, just handed to kubectl_manifest as raw YAML
# instead of jsondecode()'d into a Settings API body).

resource "helm_release" "dynatrace_operator" {
  name             = "dynatrace-operator"
  namespace        = "dynatrace"
  create_namespace = true
  repository       = "https://raw.githubusercontent.com/Dynatrace/helm-charts/master/repos/stable"
  chart            = "dynatrace-operator"

  set {
    name  = "installCRD"
    value = "true"
  }

  # Default wait=true: helm_release blocks until the release's
  # Deployments/StatefulSets report ready, which already covers the
  # dynatrace-webhook race apply_dynakube.yml's Ansible task needed an
  # explicit `kubectl rollout status` wait to avoid (see Phase "uninstall/
  # install" commit). Terraform gets this for free from the provider.
}

resource "kubernetes_secret" "dynakube" {
  metadata {
    name      = "dynakube"
    namespace = "dynatrace"
  }

  type = "Opaque"

  data = {
    apiToken        = var.DT_OPERATOR_TOKEN
    dataIngestToken = var.DT_INGEST_TOKEN
  }

  depends_on = [helm_release.dynatrace_operator]
}

resource "kubectl_manifest" "dynakube" {
  yaml_body = templatefile("${path.module}/../observability/dynatrace/dynakube/dynakube.yaml.j2", {
    DT_API_URL            = var.DT_API_URL
    DT_HOST_GROUP         = var.DT_HOST_GROUP
    DT_ENVIRONMENT        = var.DT_ENVIRONMENT
    DT_OWNED_BY           = var.DT_OWNED_BY
    K8S_DYNATRACE_CLUSTER = local.k8s_dynatrace_cluster
  })

  depends_on = [
    helm_release.dynatrace_operator,
    kubernetes_secret.dynakube,
  ]
}
