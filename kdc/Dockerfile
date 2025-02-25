FROM alpine:latest

ARG IMAGE_BUILD_TIMESTAMP
ENV IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}
RUN echo IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}

RUN apk add --no-cache krb5-server \
    krb5 \
    supervisor \ 
    tini \
    tzdata \
    bash \
    && rm -rf /var/cache/apk/*

ENV KEYTAB_DIR=/etc/security/keytabs
ENV KRB_LOG_DIR=/var/log/kerberos
ENV TZ="Australia/Sydney"

RUN mkdir -p /var/log/kerberos
RUN mkdir -p /etc/security/keytabs
RUN mkdir -p /etc/krb5kdc
RUN chmod -R 777 /etc/krb5kdc

COPY supervisord.conf /etc/supervisord.conf
COPY kadm5.acl /etc/krb5kdc/kadm5.acl
COPY kdc.conf /var/lib/krb5kdc/kdc.conf
COPY krb5.conf /etc/krb5.conf

# Kube Probes
COPY healthy /tmp/healthy

COPY run.sh /run.sh
RUN chmod a+x /run.sh

ENTRYPOINT ["/sbin/tini", "--"]

CMD ["/run.sh"]