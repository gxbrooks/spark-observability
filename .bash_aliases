#!/usr/bin/bash

# Docker aliases
alias dkill='docker rm $(docker ps -aq)'
alias dlsi='docker image ls'
alias drmi='docker rmi $(docker images -q)'


#Docker Compose aliases
# Docker Compose with project-specific env file (run from repo root or observability/)
alias dc='docker compose --env-file ./vars/contexts/observability_docker.env'
# Docker container stats table
alias dcpsstats='dc ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" | sed 1d | while read id name status; do stats=$(docker stats --no-stream --format "{{.CPUPerc}}\t{{.MemPerc}}\t{{.BlockIO}}\t{{.NetIO}}" $id); printf "%-12s %-25s %-20s %s\n" "$id" "$name" "$status" "$stats"; done | sed "1i CONTAINER ID   NAME                      STATUS               CPU%   MEM%   BLOCK I/O     NET I/O"'

# removal of containers

alias dcrm='docker rm $(docker ps -aq)'
alias dcrmid='docker rmi $(docker images -q --filter "dangling=true")'


alias dcps="docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}'"
alias dcps2="docker ps -a --format 'table {{.ID}}\t{index .Config.Labels \"com.docker.compose.service\"}\t{{.Names}}\t{{.Status}}'"

# docker ps --format '{{.ID}}' | xargs -I {} docker inspect --format '{{.Name}} {{index .Config.Labels "com.docker.compose.service"}}' {}
# alias dcpss='docker ps --format "{{.ID}}" | xargs -I {} docker inspect --format "{{.Name}} {{index .Config.Labels \"com.docker.compose.service\"}}" {}'
# alias dcpss='printf "%-12s %-15s %-15s %-15s\n" "CONTAINER_ID" "NAME" "STATUS" "SERVICE"; docker ps --format "{{.ID}}" | xargs -I {} docker inspect --format "{{.ID}}\t{{.Name}}\t{{.State.Status}}\t{{index .Config.Labels \"com.docker.compose.service\"}}" {} | awk -F"\t" "{printf \"%-12s %-15s %-15s %-15s\\n\", substr(\$1, 1, 12), \$2, \$3, \$4}"'



alias dcd='docker compose down '
alias dcdv='docker compose down -v --remove-orphans'
alias dcu='docker compose up -d'
alias dcuf='docker compose up --build --force-recreate'
alias dcb='docker compose build '
alias dcexec='docker compose exec -it '
alias dcrun='docker compose run -it '
alias dcr='docker compose restart '
alias dclogs="docker compose logs "
alias dccp="docker compose cp "
alias dcr="docker compose restart "



alias dcipython='docker compose exec \
	-e PYSPARK_DRIVER_PYTHON=ipython spark-master \
	pyspark --packages com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.32.0'


alias esapi="docker compose exec -it es01 esapi"
alias kapi="docker compose exec -it es01 kapi"

# HDFS wrapper for seamless Hadoop access
alias hdfs="/home/gxbrooks/repos/spark-observability/linux/hdfs-wrapper.sh"

alias glog="git log --pretty=format:'%h %ad | %s' --date=short --follow --all -- "
alias gtags='git for-each-ref --sort=-creatordate --format="%(align:left,width=33)%(refname:lstrip=2)%(end) %(align:left,width=12)%(creatordate:short)%(end) %(subject)" refs/tags'
alias gcsummary='git log --decorate --date=short --pretty=format:"%C(auto,yellow)[%ad] %C(auto,green)%d%C(reset) %s%n%b%n%C(auto,blue)----------------------------------------------------%C(auto,reset)"'


alias pscursor="ps -eo pid,ppid,user,%cpu,rss,vsz,comm | awk 'NR==1 {printf \"%-7s %-7s %-10s %4s %7s %10s %s\n\",\$1,\$2,\$3,\$4,\$5,\$6,\$7; next} {printf \"%-7s %-7s %-10s %4.1f %7s %10s %s\n\",\$1,\$2,\$3,\$4,\$5,\$6,\$7}'"


# Kubernetes helpers (functions — reliable kubeconfig + clear errors if kubectl/kubeconfig missing)
function _kubeconfig_default {
  if [[ -n "${KUBECONFIG:-}" ]]; then
    echo "$KUBECONFIG"
  elif [[ -f "$HOME/.kube/config" ]]; then
    echo "$HOME/.kube/config"
  elif [[ -f "/home/ansible/.kube/config" ]]; then
    echo "/home/ansible/.kube/config"
  fi
}

function k_kubectl {
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl: not installed (e.g. sudo apt install -y kubectl)" >&2
    return 127
  fi
  local kc
  kc="$(_kubeconfig_default)"
  if [[ -n "$kc" ]] && [[ ! -r "$kc" ]]; then
    echo "kubectl: kubeconfig not readable: $kc" >&2
    return 1
  fi
  if [[ -n "$kc" ]]; then
    kubectl --kubeconfig "$kc" "$@"
  else
    kubectl "$@"
  fi
}

function kwexec  { k_kubectl exec -it -n spark -c spark-worker "$@"; }
function kmexec  { k_kubectl exec -it -n spark -c spark-master "$@"; }
function kpods   { k_kubectl get pods -n spark "$@"; }
function ksvc    { k_kubectl get svc -n spark "$@"; }
function klogs   { k_kubectl logs -n spark "$@"; }

function klogsall    { k_kubectl logs -n spark --all-containers "$@"; }
function ktop        { k_kubectl top pods -n spark "$@"; }
function ktopall     { k_kubectl top pods -n spark --all-containers "$@"; }
function kdescribe   { k_kubectl describe pod -n spark "$@"; }
function kdescribeall { k_kubectl describe pod -n spark --all-containers "$@"; }
function kdelete     { k_kubectl delete pod -n spark "$@"; }
function kdeleteall  { k_kubectl delete pod -n spark --all-containers "$@"; }

# Ansible — observability host (Lab3): Docker Engine + stack deploy + start.
# Run from your control machine where `ssh ansible@lab3.lan` works (inventory: ansible_ssh_private_key_file).
_SPARK_OBS_ANSIBLE_ROOT="${SPARK_OBSERVABILITY_ROOT:-$HOME/repos/spark-observability}/ansible"
ansible_obs_lab3_docker() ( cd "$_SPARK_OBS_ANSIBLE_ROOT" && ansible-playbook -i inventory.yml playbooks/docker/install.yml --limit observability "$@" )
ansible_obs_lab3_install() ( cd "$_SPARK_OBS_ANSIBLE_ROOT" && ansible-playbook -i inventory.yml playbooks/observability/install.yml --limit observability "$@" )
ansible_obs_lab3_start()   ( cd "$_SPARK_OBS_ANSIBLE_ROOT" && ansible-playbook -i inventory.yml playbooks/observability/start.yml   --limit observability "$@" )
ansible_obs_lab3_up() {
  ansible_obs_lab3_docker "$@" || return
  ansible_obs_lab3_install "$@" || return
  ansible_obs_lab3_start "$@" || return
}
