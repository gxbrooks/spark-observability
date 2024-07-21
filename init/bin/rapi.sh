#!/usr/bin/bash

# RAPI = Run (Elastic) API

# To run:
#   rapi <method> <url_path> [ <body> ]
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

if [ "$method" == "" ] || [ "$url_path" == "" ]
then 
  echo "both the method and url_path path must be supplied"  >&2 
  echo "method=$method" >&2 
  echo "url_path=$url_path" >&2 
  exit 1
fi

if ! ( [ "$method" == "PUT" ] || [ "$method" == "GET" ] || [ "$method" == "POST" ] )
then
  echo "Method must be one of PUT, GET, or POST and not $method"  >&2 
  exit 1
fi

if [ "$method" == "PUT" ]
then
  if ! [ -f $body ] ;  then 
    echo "PUT body must be a file that exists. \"$body\" does not exist" >&2 
    exit 1
  else
    body_line="--data-binary @$body"
  fi
else 
  if [ $method == "POST" ] ; then
    if [ "$body" == "" ]; then
      body_line=""
    else 
      if ! [ -f $body ] ;  then 
        echo "POST body must be a file that exists. \"$body\" does not exist"  >&2 
        exit 1 
      else
        body_line="--data-binary @$body"
      fi
    fi    
  fi
fi

if [ -f /usr/bin/docker ]; then
  . .env # source in environment variables, especiall passwords
  command="docker compose exec -it es01 curl"
else
  command="curl"
fi



echo "Executing $method on $url_path with body '$body'" >&2 

if [ "$method" == "GET" ]
then
  # docker compose exec -it init-index curl 
  result=$($command \
            --no-progress-meter \
            --request $method "https://es01:9200/$url_path" \
            --cacert config/certs/ca/ca.crt \
            -u "elastic:${ELASTIC_PASSWORD}" \
            -H "Content-Type: application/json" \
          )
  status=$?
else
  result=$($command \
            --no-progress-meter \
            --request $method "https://es01:9200/$url_path" \
            --cacert config/certs/ca/ca.crt \
            -u "elastic:${ELASTIC_PASSWORD}" \
            -H "Content-Type: application/json"\
            $body_line \
          )
  status=$?
fi

#echo -e "Status is $status\nResult is: $result"

if [ $status -ne 0 ]; then
    echo "Error: curl failed with code $?" >&2
    exit $status
else 
  # see if HTTP request errored
  hstatus=$(echo $result | jq -r .status)
  if [ "$hstatus" == "200" ] || [ "$hstatus" == "null" ]; then
    status=0
  else 
    echo "HTTP error: $hstatus" >&2
    status=1
  fi
fi
echo $result
exit $status


