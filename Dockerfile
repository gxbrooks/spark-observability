
# required arguments to build Elasticsearch
ARG STACK_VERSION=8.7.1
from docker.elastic.co/elasticsearch/elasticsearch:${STACK_VERSION} as cert-es-base

ARG STACK_VERSION
ARG ELASTIC_PASSWORD=changeme
ARG KIBANA_PASSWORD=changeme 

RUN echo "version is  ${STACK_VERSION}"

# run with docker run --env-file ../.env [...]

RUN echo "Directory is; `pwd`"
RUN echo "User is:; `whoami`"

CMD ["/bin/bash"]
USER root
RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends jq

USER elasticsearch:root
RUN mkdir config/certs
RUN mkdir config/certs/ca
COPY --chmod=640 ./build/instances.yml config/certs/instances.yml

RUN echo "Creating CA"; 
RUN bin/elasticsearch-certutil ca --silent --pem -out config/certs/ca.zip; \
	unzip config/certs/ca.zip -d config/certs; 
	
RUN echo "Creating certs";
RUN bin/elasticsearch-certutil cert --silent --pem -out config/certs/certs.zip --in config/certs/instances.yml --ca-cert config/certs/ca/ca.crt --ca-key config/certs/ca/ca.key
RUN unzip config/certs/certs.zip -d config/certs

RUN echo "Setting file permissions" 
#RUN chown -R root:root config/certs;
RUN find ./config/certs -type d -exec chmod 750 \{\} \;;
RUN find ./config/certs -type f -exec chmod 640 \{\} \;;

# expose the same ports as per the original Dockerfile build
EXPOSE 9200

#Do we need 9300? It's seems to be a standard port for Elasticsearch
EXPOSE 9300

CMD ["eswrapper"]

USER elasticsearch:root