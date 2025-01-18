FROM python:3.10-bullseye AS spark-base


# TODO: Need a service account for Spark

ARG SPARK_VERSION
ARG SPARK_MASTER
ARG SPARK_HOME
ARG SPARK_MASTER_HOST
ARG SPARK_MASTER_PORT
ARG PYSPARK_PYTHON
ARG HADOOP_HOME
ARG ELASTIC_AGENT_BASE
ARG ELASTIC_AGENT_STACK_VERSION


ENV SPARK_MASTER=${SPARK_MASTER}
ENV SPARK_MASTER_HOST=${SPARK_MASTER_HOST}
ENV SPARK_MASTER_PORT=${SPARK_MASTER_HOST}
ENV PYSPARK_PYTHON=${PYSPARK_PYTHON}
ENV SPARK_HOME=${SPARK_HOME}
ENV PATH="${SPARK_HOME}/sbin:${SPARK_HOME}/bin:${PATH}"


# Install tools required by the OS
RUN apt-get update  \
    && apt-get install -y --no-install-recommends \
      sudo \
      curl \
      vim \
      unzip \
      rsync \
      openjdk-11-jdk \
      build-essential \
      software-properties-common \
      ssh \
	  ipython3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*


# Setup the directories for our Spark and Hadoop installations
ENV SPARK_HOME=${SPARK_HOME}
ENV HADOOP_HOME=${HADOOP_HOME}

RUN mkdir -p ${HADOOP_HOME} && mkdir -p ${SPARK_HOME}
WORKDIR ${SPARK_HOME}

# Download and install Spark
RUN curl https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz -o spark-${SPARK_VERSION}-bin-hadoop3.tgz \
 && tar xvzf spark-${SPARK_VERSION}-bin-hadoop3.tgz --directory /opt/spark --strip-components 1 \
 && rm -rf spark-${SPARK_VERSION}-bin-hadoop3.tgz

FROM spark-base AS pyspark
 
# Install python deps
COPY requirements/requirements.txt .
RUN pip3 install -r requirements.txt

# Copy the default configurations into $SPARK_HOME/conf
COPY conf/spark-defaults.conf "$SPARK_HOME/conf"
#COPY conf/log4j2.properties "$SPARK_HOME/conf"

RUN chmod u+x /opt/spark/sbin/* && \
    chmod u+x /opt/spark/bin/*

# PYTHONPATH is undefined at this point and only consists of $SPARK_HOME/python
ENV PYTHONPATH=$SPARK_HOME/python


#################################################################################
#
# Install the Elastic Agent

# TODO: Need a service account of Elastic Agent

# See https://www.elastic.co/guide/en/fleet/8.15/install-standalone-elastic-agent.html
# keep the tar file and extracted directories outside the installation directory. 

# Setup Spark related environment variables
ENV ELASTIC_AGENT_HOME=${ELASTIC_AGENT_BASE}/elastic-agent
ENV ELASTIC_AGENT_STACK_VERSION=${ELASTIC_AGENT_STACK_VERSION}

RUN mkdir -p ${ELASTIC_AGENT_HOME}
WORKDIR ${ELASTIC_AGENT_HOME}

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
	systemctl \
    && rm -rf /var/lib/apt/lists/*

# Download and install the Elastic Agent
RUN curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${ELASTIC_AGENT_STACK_VERSION}-amd64.deb \
    && dpkg -i elastic-agent-${ELASTIC_AGENT_STACK_VERSION}-amd64.deb \
    && rm elastic-agent-${ELASTIC_AGENT_STACK_VERSION}-amd64.deb

RUN systemctl enable elastic-agent 
# enable in the image, but need to start as part of the entrypoint wrapper

WORKDIR ${SPARK_HOME}

# Copy the entrypoint which starts elasstic-agent and then invokes the approriate
# Spark process
COPY entrypoint.sh .
RUN chmod a+x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]

