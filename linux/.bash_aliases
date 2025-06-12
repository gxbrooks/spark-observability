#!/usr/bin/bash

alias dcps="docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}'"
alias dcps2="docker ps -a --format 'table {{.ID}}\t{index .Config.Labels \"com.docker.compose.service\"}\t{{.Names}}\t{{.Status}}'"

# docker ps --format '{{.ID}}' | xargs -I {} docker inspect --format '{{.Name}} {{index .Config.Labels "com.docker.compose.service"}}' {}
# alias dcpss='docker ps --format "{{.ID}}" | xargs -I {} docker inspect --format "{{.Name}} {{index .Config.Labels \"com.docker.compose.service\"}}" {}'
# alias dcpss='printf "%-12s %-15s %-15s %-15s\n" "CONTAINER_ID" "NAME" "STATUS" "SERVICE"; docker ps --format "{{.ID}}" | xargs -I {} docker inspect --format "{{.ID}}\t{{.Name}}\t{{.State.Status}}\t{{index .Config.Labels \"com.docker.compose.service\"}}" {} | awk -F"\t" "{printf \"%-12s %-15s %-15s %-15s\\n\", substr(\$1, 1, 12), \$2, \$3, \$4}"'

alias dckill='docker rm $(docker ps -aq)'

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

Images
alias dlsi='docker image ls'
alias drmi='docker rmi $(docker images -q)'
# removal of containers
alias dcrm='docker rm $(docker ps -aq)'
alias dcrmid='docker rmi $(docker images -q --filter "dangling=true")'

alias dcipython='docker compose exec \
	-e PYSPARK_DRIVER_PYTHON=ipython spark-master \
	pyspark --packages com.google.cloud.spark:spark-bigquery-with-dependencies_2.12:0.32.0'

alias esapi="docker compose exec -it es01 esapi"
alias kapi="docker compose exec -it es01 kapi"

