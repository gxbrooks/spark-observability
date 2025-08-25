FROM python:3.11-bullseye AS spark-base

# TODO: Need a service account for Spark

ARG SPARK_VERSION
ARG SPARK_HOME
ARG PYSPARK_PYTHON
ARG HADOOP_HOME

# setup the structure of the implementation
ENV SPARK_HOME=${SPARK_HOME:-/opt/spark}
ENV HADOOP_HOME=${HADOOP_HOME:-/opt/hadoop}

ENV PYSPARK_PYTHON=${PYSPARK_PYTHON:-python3}

ENV PATH="${SPARK_HOME}/sbin:${SPARK_HOME}/bin:${PATH}"
# TODO: looks like a vestigal variable definition probably for access to GSOD data
ENV GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS}"

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
# TODO: what is ${HADOOP_HOME} for? It does not seem to be used
# Sourced from https://github.com/mrn-aglic/pyspark-playground/blob/main/Dockerfile
RUN mkdir -p ${HADOOP_HOME} && mkdir -p ${SPARK_HOME}
WORKDIR ${SPARK_HOME}

# Download and install Spark
RUN curl https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz -o spark-${SPARK_VERSION}-bin-hadoop3.tgz \
 && tar xvzf spark-${SPARK_VERSION}-bin-hadoop3.tgz --directory /opt/spark --strip-components 1 \
 && rm -rf spark-${SPARK_VERSION}-bin-hadoop3.tgz

FROM spark-base AS pyspark
 
# Install python deps
# Gave up on pip-compile-multi and removed requirement.txt to install
# requirements.in directly. We'll see if the latest versions break anything
# TODO: Copying miscelaneous files into the base of an install does not 
# seem appropriate. 
COPY requirements/requirements.in .
RUN pip3 install -r requirements.in

# Copy the default configurations into $SPARK_HOME/conf
COPY conf/spark-defaults.conf "$SPARK_HOME/conf"
#COPY conf/log4j2.properties "$SPARK_HOME/conf"

RUN chmod u+x /opt/spark/sbin/* && \
    chmod u+x /opt/spark/bin/*

# PYTHONPATH is undefined at this point and only consists of $SPARK_HOME/python
ENV PYTHONPATH=$SPARK_HOME/python


WORKDIR ${SPARK_HOME}

# Copy the entrypoint which starts elasstic-agent and then invokes the approriate
# Spark process
COPY entrypoint.sh .
RUN chmod a+x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]

