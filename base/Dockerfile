# FROM debian:buster

#Docker running on macOS with an ARM64 (Apple Silicon) CPU.
FROM arm64v8/debian:buster-slim

# Install prerequisites
# We create the /usr/share/man/man1 and /usr/share/man/man2 directories to avoid dependency issues during the OpenJDK installation.
RUN apt-get update && apt-get install -y ca-certificates-java && \
    mkdir -p /usr/share/man/man1 /usr/share/man/man2

# Install OpenJDK 11 and other packages
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openjdk-11-jdk \
      net-tools \
      curl \
      netcat \
      gnupg \
      libsnappy-dev \
    && rm -rf /var/lib/apt/lists/*

# (for 64-bit systems)      
# ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64/

# (for ARM64 systems)
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-arm64/

RUN curl -O https://dist.apache.org/repos/dist/release/hadoop/common/KEYS

RUN gpg --import KEYS

ENV HADOOP_VERSION 3.4.0
ENV HADOOP_URL https://www.apache.org/dist/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz

RUN set -x \
    && curl -fSL "$HADOOP_URL" -o /tmp/hadoop.tar.gz \
    && curl -fSL "$HADOOP_URL.asc" -o /tmp/hadoop.tar.gz.asc \
    && gpg --verify /tmp/hadoop.tar.gz.asc \
    && tar -xvf /tmp/hadoop.tar.gz -C /opt/ \
    && rm /tmp/hadoop.tar.gz*

RUN ln -s /opt/hadoop-$HADOOP_VERSION/etc/hadoop /etc/hadoop

RUN mkdir /opt/hadoop-$HADOOP_VERSION/logs

ENV HADOOP_HOME=/opt/hadoop-$HADOOP_VERSION
ENV HADOOP_CONF_DIR=/etc/hadoop
ENV USER=root
ENV PATH $HADOOP_HOME/bin/:$PATH
