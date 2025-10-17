# Custom Spark image with Python 3.11
# Uses SPARK_VERSION build arg to select base image

ARG SPARK_VERSION=4.0.1
FROM docker.io/apache/spark:${SPARK_VERSION}

USER root

# Install build dependencies for Python
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wget build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
    libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev \
    libbz2-dev liblzma-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Download and compile Python 3.11.10
RUN cd /tmp && \
    wget https://www.python.org/ftp/python/3.11.10/Python-3.11.10.tgz && \
    tar -xzf Python-3.11.10.tgz && \
    cd Python-3.11.10 && \
    ./configure --enable-optimizations --prefix=/usr/local && \
    make -j$(nproc) && \
    make altinstall && \
    cd / && rm -rf /tmp/Python-3.11.10*

# Set Python 3.11 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.11 1 && \
    update-alternatives --set python3 /usr/local/bin/python3.11 && \
    ln -sf /usr/local/bin/python3.11 /usr/bin/python

# Set environment variables
ENV PYSPARK_PYTHON=/usr/local/bin/python3.11
ENV PYSPARK_DRIVER_PYTHON=/usr/local/bin/python3.11

# Install pip for Python 3.11
RUN /usr/local/bin/python3.11 -m ensurepip && \
    /usr/local/bin/python3.11 -m pip install --upgrade pip

# Install Python packages
RUN /usr/local/bin/python3.11 -m pip install --no-cache-dir \
    numpy \
    pandas \
    pyarrow

# Verify Python version
RUN python3 --version && echo "PySpark will use: $PYSPARK_PYTHON"

# Image runs as root by default, matching Apache Spark base image
# Kubernetes securityContext will set the appropriate user if needed

WORKDIR /opt/spark
