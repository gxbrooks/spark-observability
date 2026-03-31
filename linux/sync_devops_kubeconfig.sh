#!/usr/bin/env bash
# Sync ~/.kube/config from the control plane's /etc/kubernetes/admin.conf over SSH.
#
# Canonical cluster PKI and admin credentials live on the kubernetes_master host under
# /etc/kubernetes/pki/ and /etc/kubernetes/admin.conf (see linux/docs/Kubernetes_PKI_and_kubeconfig.md).
# Worker nodes (e.g. Lab1/Lab2) do not hold kubernetes-admin private keys.
#
# Environment (from vars/contexts/devops_env.sh / spark_client_env.sh):
#   KUBERNETES_API_SERVER       — API hostname only, e.g. Lab3.lan (optional if URL set)
#   KUBERNETES_API_SERVER_URL   — full URL, e.g. https://Lab3.lan:6443
#   KUBECONFIG_SYNC_USER        — SSH user on control plane (default: ansible)
#   KUBECONFIG_SYNC_DISABLED    — set to 1 to skip
#
# Usage: source this file from .bashrc, or run: bash linux/sync_devops_kubeconfig.sh

sync_devops_kubeconfig() {
  [[ "${KUBECONFIG_SYNC_DISABLED:-0}" == "1" ]] && return 0

  local url=""
  if [[ -n "${KUBERNETES_API_SERVER_URL:-}" ]]; then
    url="$KUBERNETES_API_SERVER_URL"
  elif [[ -n "${KUBERNETES_API_SERVER:-}" ]]; then
    if [[ "${KUBERNETES_API_SERVER}" =~ ^https?:// ]]; then
      url="${KUBERNETES_API_SERVER}"
    else
      url="https://${KUBERNETES_API_SERVER}:6443"
    fi
  else
    return 0
  fi

  local cp_host=""
  if [[ "$url" =~ ^https?://([^/:]+) ]]; then
    cp_host="${BASH_REMATCH[1]}"
  else
    return 0
  fi

  local ssh_user="${KUBECONFIG_SYNC_USER:-ansible}"
  local stamp_file="${HOME}/.kube/.spark-observability-admin.conf.sha256"
  mkdir -p "${HOME}/.kube"

  # Same host as control plane: use local admin.conf (no SSH)
  if [[ -r /etc/kubernetes/admin.conf ]]; then
    local local_sum
    local_sum=$(sha256sum /etc/kubernetes/admin.conf 2>/dev/null | awk '{print $1}')
    [[ -z "$local_sum" ]] && return 0
    local prev
    prev=$(cat "$stamp_file" 2>/dev/null || true)
    if [[ "$local_sum" == "$prev" ]] && [[ -f "${HOME}/.kube/config" ]]; then
      _kube_set_server_url "$url" || true
      return 0
    fi
    cp /etc/kubernetes/admin.conf "${HOME}/.kube/config"
    chmod 600 "${HOME}/.kube/config" 2>/dev/null || true
    echo "$local_sum" >"$stamp_file"
    _kube_set_server_url "$url" || true
    return 0
  fi

  local remote_sum
  remote_sum=$(
    ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new \
      "${ssh_user}@${cp_host}" 'sha256sum /etc/kubernetes/admin.conf 2>/dev/null' </dev/null | awk '{print $1}'
  )
  [[ -z "$remote_sum" ]] && return 0

  local prev
  prev=$(cat "$stamp_file" 2>/dev/null || true)
  if [[ "$remote_sum" == "$prev" ]] && [[ -f "${HOME}/.kube/config" ]]; then
    _kube_set_server_url "$url" || true
    return 0
  fi

  if ! scp -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new \
    "${ssh_user}@${cp_host}:/etc/kubernetes/admin.conf" "${HOME}/.kube/config.tmp" 2>/dev/null; then
    return 0
  fi
  mv -f "${HOME}/.kube/config.tmp" "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config" 2>/dev/null || true
  echo "$remote_sum" >"$stamp_file"
  _kube_set_server_url "$url" || true
}

_kube_set_server_url() {
  local surl="$1"
  [[ -f "${HOME}/.kube/config" ]] || return 1
  if command -v kubectl >/dev/null 2>&1; then
    kubectl config set-cluster kubernetes --server="$surl" --kubeconfig="${HOME}/.kube/config" >/dev/null 2>&1 || true
  else
    sed -i "s|^[[:space:]]*server: https://.*:6443|    server: ${surl}|" "${HOME}/.kube/config" 2>/dev/null || true
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  sync_devops_kubeconfig
fi
