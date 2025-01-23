#!/usr/bin/bash

# esapi = Run (Elastic) API

# To run:
#   esapi <method> <url_path> [ <body> ]
#
# This somewhat mimics the syntax of typical examples that specify the HTTP request and optional JSON 
# body for the request.
#
# Invoke from the docker compose directory or within a Docker Elasticsearch container
#
# Error output is redirected to standard error to allow piping commands through jq.
#


method=$1
url_path=$2
body=$3

# TODO
# - check  for docker login

if [ "$method" == "" ] || [ "${url_path}" == "" ]
then 
  echo `date -u +%Y-%m-%dT%H:%M:%S.%N` " | both the method and url_path path must be supplied"  >&2 
  echo `date -u +%Y-%m-%dT%H:%M:%S.%N` " | Method=$method" >&2 
  echo `date -u +%Y-%m-%dT%H:%M:%S.%N` " | URL Path=${url_path}" >&2 
  exit 1
fi


if [[ "${url_path:0:1}" != "/" ]]; 
then
  echo `date -u +%Y-%m-%dT%H:%M:%S.%N` " | The URL path '${url_path}' must begin with a '/'"  >&2 
  exit 1
fi

if ! ( [ "$method" == "PUT" ] || [ "$method" == "GET" ] || [ "$method" == "POST" ] || [ "$method" == "DELETE" ] )
then
  echo `date -u +%Y-%m-%dT%H:%M:%S.%N` "Method must be one of PUT, GET, or POST and not $method"  >&2 
  exit 1
fi

if [ "$method" == "PUT" ]
then
  if ! [ -f ${body} ] ;  then 
    echo `date -u +%Y-%m-%dT%H:%M:%S.%N` " | PUT body must be a file that exists. \"${body}\" does not exist" >&2 
    exit 1
  else
    body_line="--data-binary @/etc/${body}"
	echo `date -u +%Y-%m-%dT%H:%M:%S.%N` " | Executing $method on ${url_path} with body '/etc/${body}'" >&2 
  fi
else 
  # for GET and POST bodies are optional - even GETs
  if [ "${body}" == "" ]; then
    body_line=""
	echo `date -u +%Y-%m-%dT%H:%M:%S.%N` " | Executing $method on ${url_path}" >&2 
  else 
    if ! [ -f ${body} ] ;  then 
      echo `date -u +%Y-%m-%dT%H:%M:%S.%N` " | GET or POST body must be a file that exists. \"${body}\" does not exist"  >&2 
      exit 1 
    else
      body_line="--data-binary @/etc/${body}"
	  echo `date -u +%Y-%m-%dT%H:%M:%S.%N` " | Executing $method on ${url_path} with body '/etc/${body}'" >&2 
    fi
  fi    
fi

echo body_line=${body_line} >&2

if [ -f /usr/bin/docker ]; then
  . .env # source in environment variables, especiall passwords
  command="docker compose exec -it grafana curl"
else
  command="curl"
fi

echo command=${command} >&2 

url="http://localhost:3000${url_path}"
echo url=$url >&2 

if [ "${body}_line" == "" ]
then
  # docker compose exec -it init-index curl 
  result=$($command #--write-out "%{http_code}"\
            --no-progress-meter \
            --request $method ${url} \
            --cacert config/certs/ca/ca.crt \
            -u "${GF_SECURITY_ADMIN_USER}:${GF_SECURITY_ADMIN_PASSWORD}" 
            -H "Content-Type: application/json" \
          )
  status=$?
else
  result=$($command \
            --no-progress-meter \
            --request $method ${url} \
            --cacert config/certs/ca/ca.crt \
            -u "${GF_SECURITY_ADMIN_USER}:${GF_SECURITY_ADMIN_PASSWORD}" \
            -H "Content-Type: application/json" \
            ${body_line} \
          )
  status=$?
fi

if [ $status -ne 0 ]; then
    echo `date -u +%Y-%m-%dT%H:%M:%S.%N` " | Error: curl failed with code $status" >&2
    exit $status
else 
    echo `date -u +%Y-%m-%dT%H:%M:%S.%N` " | curl completed successfully" >&2
fi
echo $result
exit $status
