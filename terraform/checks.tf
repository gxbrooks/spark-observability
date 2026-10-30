# "test": behavioral pass/fail, mirroring
# ansible/playbooks/observability/dynatrace/test.yml. Terraform's native
# `check` block (1.5+) is the idiomatic match -- runs on every plan/apply,
# reports pass/fail without halting the run (unlike a resource
# precondition/postcondition, which would fail the apply outright). That
# "report, don't block" behavior is actually the right fit for "test" as
# the standards doc defines it (a baseline health read, not a gate) --
# and it's also why diagnose.tf's data sources are reused here rather
# than duplicated: the standards doc states diagnose must be a superset
# of test's checks, so test asserting on the same facts diagnose reports
# keeps that relationship real instead of two checks silently drifting
# apart over time.
#
# Not replicated: test.yml's OTLP ingest endpoint POST check
# (hashicorp/http's data source is GET-only, no POST support) and the
# webhook TLS certificate expiry check (would need to read the
# dynatrace-webhook-certs Secret and parse x509 -- doable, not done
# here). Tenant/token validity isn't a separate check below because it's
# already implicit: every dynatrace_generic_setting and
# data.kubernetes_resource.dynakube read in this config would fail
# outright on an invalid token, long before check evaluation.

check "dynakube_running" {
  assert {
    condition     = data.kubernetes_resource.dynakube.object.status.phase == "Running"
    error_message = "DynaKube phase is '${try(data.kubernetes_resource.dynakube.object.status.phase, "unknown")}', expected 'Running'."
  }
}

check "operator_ready_when_running" {
  assert {
    # Only meaningful while dynatrace_running=true -- at 0 desired
    # replicas (stopped), 0 ready is correct, not a failure.
    condition = !var.dynatrace_running || (
      coalesce(try(data.kubernetes_resource.operator_deployment.object.status.readyReplicas, null), 0)
      == data.kubernetes_resource.operator_deployment.object.spec.replicas
    )
    error_message = "Dynatrace Operator does not have all replicas ready."
  }
}

check "webhook_ready_when_running" {
  assert {
    condition = !var.dynatrace_running || (
      coalesce(try(data.kubernetes_resource.webhook_deployment.object.status.readyReplicas, null), 0)
      == data.kubernetes_resource.webhook_deployment.object.spec.replicas
    )
    error_message = "Dynatrace webhook does not have all replicas ready."
  }
}

check "activegate_ready" {
  # Added after this check block caught dynakube_running failing live:
  # ActiveGate was crash-looping (0/1 ready, 500+ restarts over 2+ days)
  # and nothing in this config was tracking the StatefulSet at all until
  # then -- diagnostics.tf only had Deployments and DaemonSets. Root
  # cause not yet investigated (kubelet events point to repeated pod
  # sandbox recreation, consistent with node resource pressure on Lab3,
  # which also runs NFS/Docker/the whole observability Compose stack --
  # not confirmed).
  assert {
    condition = (
      data.kubernetes_resource.activegate.object.status.readyReplicas
      == data.kubernetes_resource.activegate.object.spec.replicas
    )
    error_message = "Dynatrace ActiveGate does not have all replicas ready."
  }
}

check "oneagent_daemonset_ready" {
  # Not gated by dynatrace_running: OneAgent is a separate DaemonSet the
  # Operator created, not scaled by the operator/webhook replica toggle
  # (see dynatrace_lifecycle.tf) -- same as Ansible's "this only scales
  # down the operator deployment" semantics.
  assert {
    condition = (
      data.kubernetes_resource.oneagent_daemonset.object.status.numberReady
      == data.kubernetes_resource.oneagent_daemonset.object.status.desiredNumberScheduled
    )
    error_message = "OneAgent DaemonSet does not have all pods ready."
  }
}
