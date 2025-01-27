#!/usr/bin/bash

alias dcps="docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Status}}'"

alias dckill='docker rm $(docker ps -aq)'

alias dcd='docker compose down '
alias dcdv='docker compose down -v'
alias dcu='docker compose up '
alias dcuf='docker compose up --build --force-recreate'
alias dcb='docker compose build '
alias dcexec='docker compose exec -it '
alias dcrun='docker compose run -it '
alias dcr='docker compose restart '
alias dclog="docker compose logs "

alias esapi="docker compose exec -it es01 esapi"
alias kapi="docker compose exec -it es01 kapi"

