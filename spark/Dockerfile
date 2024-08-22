FROM python:3.10-bullseye as spark-base

ARG SPARK_VERSION=3.5.1

# Install tools required by the OS
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      sudo \
      curl \
      vim \
      unzip \
      rsync \
      openjdk-11-jdk \
      build-essential \
      software-properties-common \
      ssh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*


# Setup the directories for our Spark and Hadoop installations
ENV SPARK_HOME=${SPARK_HOME:-"/opt/spark"}
ENV HADOOP_HOME=${HADOOP_HOME:-"/opt/hadoop"}

RUN mkdir -p ${HADOOP_HOME} && mkdir -p ${SPARK_HOME}
WORKDIR ${SPARK_HOME}

# Download and install Spark
RUN curl https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz -o spark-${SPARK_VERSION}-bin-hadoop3.tgz \
 && tar xvzf spark-${SPARK_VERSION}-bin-hadoop3.tgz --directory /opt/spark --strip-components 1 \
 && rm -rf spark-${SPARK_VERSION}-bin-hadoop3.tgz


FROM spark-base as pyspark

# Install python deps
COPY requirements/requirements.txt .
RUN pip3 install -r requirements.txt

# Setup Spark related environment variables
ENV PATH="/opt/spark/sbin:/opt/spark/bin:${PATH}"
ENV SPARK_MASTER="spark://spark-master:7077"
ENV SPARK_MASTER_HOST spark-master
ENV SPARK_MASTER_PORT 7077
ENV PYSPARK_PYTHON python3

# Copy the default configurations into $SPARK_HOME/conf
COPY conf/spark-defaults.conf "$SPARK_HOME/conf"

RUN chmod u+x /opt/spark/sbin/* && \
    chmod u+x /opt/spark/bin/*

ENV PYTHONPATH=$SPARK_HOME/python/:$PYTHONPATH

# Copy appropriate entrypoint script
COPY entrypoint.sh .
ENTRYPOINT ["./entrypoint.sh"]

###########################
#
# Install the elastic agent
#
# keep the tar file and extracted directories outside the installation directory. 
ENV ELASTIC_HOME=${ELASTIC_HOME:-"/opt/Elastic"}
WORKDIR ${ELASTIC_HOME}
RUN mkdir -p ${ELASTIC_HOME}

# Download and install the Elastic Agent
RUN curl -L -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-8.15.0-linux-x86_64.tar.gz \
    && tar xzvf elastic-agent-8.15.0-linux-x86_64.tar.gz \
    && cd elastic-agent-8.15.0-linux-x86_64 \
    && ./elastic-agent install --non-interactive 

# Clean up
RUN rm -rf elastic-agent-8.15.0-linux-x86_64.tar.gz
# probably should clean up resulting elastic-agent-8.15.0-linux-x86_64 directory


WORKDIR ${SPARK_HOME}
# Copy appropriate entrypoint script
COPY entrypoint.sh .
ENTRYPOINT ["./entrypoint.sh"]