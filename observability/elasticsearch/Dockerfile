# required arguments to build Elasticsearch
ARG STACK_VERSION

FROM docker.elastic.co/elasticsearch/elasticsearch:${STACK_VERSION}

USER root:root

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# required to run the API utilities kapi and esapi
ENV PATH=${PATH}:/opt/shared/bin

USER elasticsearch:root

