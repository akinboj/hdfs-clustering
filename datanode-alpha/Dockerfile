FROM fhirfactory/pegacorn-base-hadoop:1.0.0

ARG IMAGE_BUILD_TIMESTAMP
ENV IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}
RUN echo IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}

# Install Kerberos client
RUN apk add --update --no-cache krb5 \
    krb5-pkinit \
    bash \
    && rm -rf /var/cache/apk/*

HEALTHCHECK CMD curl -f http://localhost:9864/ || exit 1

ENV MULTIHOMED_NETWORK=1
ENV HDFS_CONF_dfs_datanode_data_dir=file:///hadoop/dfs/datanode
ENV HDFS_KEYTAB_DIR=/etc/security/hdfs-keytabs
ENV ADMIN_KEYTAB_DIR=/etc/security/admin-keytab
ENV CERTS=/etc/hadoop/ssl
ENV TZ="Australia/Sydney"

RUN mkdir -p /hadoop/dfs/datanode
RUN mkdir -p /etc/hadoop/ssl
RUN mkdir -p /var/log/kerberos
RUN mkdir -p /etc/security/admin-keytab
RUN mkdir -p /etc/security/hdfs-keytabs

# Kerberos configuration
COPY krb5.conf /etc/krb5.conf
RUN chmod -R 444 /etc/hadoop/ssl
COPY ssl-server.xml /etc/hadoop/ssl-server.xml
COPY ssl-client.xml /etc/hadoop/ssl-client.xml

# Copy modified entrypoint script
COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]