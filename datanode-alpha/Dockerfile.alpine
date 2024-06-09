FROM fhirfactory/pegacorn-base-hadoop:1.0.0

# Install Kerberos client
RUN apk add --update --no-cache krb5 \
    && rm -rf /var/cache/apk/*

HEALTHCHECK CMD curl -f http://localhost:9864/ || exit 1

ENV MULTIHOMED_NETWORK=1
ENV HDFS_CONF_dfs_datanode_data_dir=file:///hadoop/dfs/datanode
ENV KEYTAB_DIR=/etc/security/keytabs
ENV CERTS=/etc/hadoop/ssl
ENV TZ="Australia/Sydney"

RUN mkdir -p /hadoop/dfs/datanode

# Create a group and user and disable user login
RUN addgroup -g 1000 -S jboss && adduser -u 1000 -S jboss -G jboss -D -s /sbin/nologin jboss

# Kerberos configuration
COPY krb5.conf /etc/krb5.conf
RUN mkdir -p /var/log/kerberos
RUN mkdir -p /etc/security/keytabs
RUN mkdir -p /etc/hadoop/ssl
RUN chmod -R 444 /etc/hadoop/ssl
COPY ssl-server.xml /etc/hadoop/ssl-server.xml

ARG IMAGE_BUILD_TIMESTAMP
ENV IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}
RUN echo IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}

# Hadoop ports
EXPOSE 9865 9866 9867

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]