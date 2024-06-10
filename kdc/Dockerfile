FROM arm64v8/debian:buster-slim

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        krb5-kdc \
        krb5-admin-server \
        krb5-config \
        net-tools \
        curl \
        netcat \
        gnupg \
        libsnappy-dev \
        ntp \
        tzdata \
        supervisor \
    && rm -rf /var/lib/apt/lists/*

ENV KEYTAB_DIR=/etc/security/keytabs
ENV KRB_LOG_DIR=/var/log/kerberos
ENV TZ=Australia/Sydney

RUN mkdir -p /var/log/kerberos
RUN mkdir -p /etc/security/keytabs
RUN mkdir -p /etc/krb5kdc
RUN chmod -R 777 /etc/krb5kdc

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY kadm5.acl /etc/krb5kdc/kadm5.acl
COPY kdc.conf /var/lib/krb5kdc/kdc.conf
COPY krb5.conf /etc/krb5.conf

# Kube Probes
COPY healthy /tmp/healthy

ARG IMAGE_BUILD_TIMESTAMP
ENV IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}
RUN echo IMAGE_BUILD_TIMESTAMP=${IMAGE_BUILD_TIMESTAMP}

COPY run.sh /run.sh
RUN chmod a+x /run.sh

ENTRYPOINT ["/run.sh"]

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]