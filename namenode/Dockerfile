FROM fhirfactory/pegacorn-base-hadoop:1.0.0

HEALTHCHECK CMD curl -f http://localhost:9871/ || exit 1

ENV MULTIHOMED_NETWORK=1
ENV HDFS_CONF_dfs_namenode_name_dir=file:///hadoop/dfs/namenode
ENV KEYTAB_DIR=/etc/security/keytabs
ENV CERTS=/etc/hadoop/ssl
ENV TZ="Australia/Sydney"

RUN mkdir -p /hadoop/dfs/namenode
RUN mkdir -p /etc/hadoop/ssl

# Install Kerberos client
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        krb5-user \
        libpam-krb5 \
        libpam-ccreds \
        openssl \
    && rm -rf /var/lib/apt/lists/*

# Install multiple network diagnostic tools
RUN apt-get update && \
    apt-get install -y \
    iputils-ping \
    telnet \
    net-tools \
    traceroute \
    dnsutils \
    procps \
    tzdata \
    && rm -rf /var/lib/apt/lists/*  # Clean up to reduce layer size

# Kerberos and TLS configuration
COPY krb5.conf /etc/krb5.conf
RUN mkdir -p /var/log/kerberos
RUN mkdir -p /etc/security/keytabs
RUN mkdir -p /etc/hadoop/ssl
RUN chmod -R 444 /etc/hadoop/ssl
COPY ssl-server.xml /etc/hadoop/ssl-server.xml
COPY ssl-client.xml /etc/hadoop/ssl-client.xml

ARG IMAGE_BUILD_TIMESTAMP
ENV IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}
RUN echo IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}

ENV SERVER_ADDRESS=pegacorn-fhirplace-namenode-0.pegacorn-fhirplace-namenode.site-a.svc.cluster.local

# Hadoop ports
EXPOSE 9000 9820 9871

COPY run.sh /run.sh
RUN chmod a+x /run.sh

ENTRYPOINT ["/run.sh"]