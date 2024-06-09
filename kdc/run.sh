#!/bin/sh

set -e

# Kerberos KDC server configuration
# Ref: https://github.com/dosvath/kerberos-containers/blob/master/kdc-server/init-script.sh

sed -i "s/realmValue/${REALM}/g" /var/lib/krb5kdc/kdc.conf
sed -i "s/realmValue/${REALM}/g" /etc/krb5.conf
sed -i "s/kdcserver/${MY_POD_NAME}.${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE}/g" /etc/krb5.conf
sed -i "s/kdcadmin/${MY_POD_NAME}.${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE}/g" /etc/krb5.conf

echo "==== Creating realm ==============================================================="
echo "==================================================================================="
KADMIN_PRINCIPAL=root/admin
KADMIN_PRINCIPAL_FULL=$KADMIN_PRINCIPAL@$REALM
MASTER_PASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1)

kdb5_util create -r "$REALM" -s -P ${MASTER_PASSWORD}
echo ""

echo "==================================================================================="
echo "======== Creating admin account ==================================================="
echo "==================================================================================="
echo "Adding $KADMIN_PRINCIPAL principal"
echo ""
kadmin.local -q "addprinc -pw ${MASTER_PASSWORD} ${KADMIN_PRINCIPAL_FULL}"
echo ""

echo "========== Writing keytab to ${KEYTAB_DIR} ========== "
# Namenode Keytab
kadmin.local -q "add_principal -randkey  nn/pegacorn-fhirplace-namenode-0.pegacorn-fhirplace-namenode.site-a.svc.cluster.local@${REALM}"
kadmin.local -q "ktadd -norandkey -k hdfs.keytab nn/pegacorn-fhirplace-namenode-0.pegacorn-fhirplace-namenode.site-a.svc.cluster.local"

# Datanode alpha Keytab
kadmin.local -q "add_principal -randkey  dna/pegacorn-fhirplace-datanode-alpha-0.pegacorn-fhirplace-datanode-alpha.site-a.svc.cluster.local@${REALM}"
kadmin.local -q "ktadd -norandkey -k hdfs.keytab dna/pegacorn-fhirplace-datanode-alpha-0.pegacorn-fhirplace-datanode-alpha.site-a.svc.cluster.local"

# Datanode beta Keytab
kadmin.local -q "add_principal -randkey  dnb/pegacorn-fhirplace-datanode-beta-0.pegacorn-fhirplace-datanode-beta.site-a.svc.cluster.local@${REALM}"
kadmin.local -q "ktadd -norandkey -k hdfs.keytab dnb/pegacorn-fhirplace-datanode-beta-0.pegacorn-fhirplace-datanode-beta.site-a.svc.cluster.local"

# SPNEGO keytab
kadmin.local -q "add_principal -randkey  HTTP/pegacorn-fhirplace-namenode-0.pegacorn-fhirplace-namenode.site-a.svc.cluster.local@${REALM}"
kadmin.local -q "ktadd -norandkey -k http.hdfs.keytab HTTP/pegacorn-fhirplace-namenode-0.pegacorn-fhirplace-namenode.site-a.svc.cluster.local"

# JBoss client Keytab
kadmin.local -q "add_principal -randkey  jboss@${REALM}"
kadmin.local -q "ktadd -norandkey -k jboss.hdfs.keytab jboss"
echo ""

echo "==================================================================================="
echo "================ Moving keytab files to mount location ============================"
echo ""
mv hdfs.keytab ${KEYTAB_DIR}
mv jboss.hdfs.keytab ${KEYTAB_DIR}
mv http.hdfs.keytab ${KEYTAB_DIR}
ls -lah ${KEYTAB_DIR}

echo "==================================================================================="
echo "========== Merging of the Keytab files with HTTP Keytab file ======================"
echo ""
printf "%b" "read_kt ${KEYTAB_DIR}/hdfs.keytab\nread_kt ${KEYTAB_DIR}/http.hdfs.keytab\nwrite_kt ${KEYTAB_DIR}/merged-krb5.keytab\nquit" | ktutil
printf "%b" "read_kt ${KEYTAB_DIR}/hdfs.keytab\nread_kt ${KEYTAB_DIR}/jboss.hdfs.keytab\nwrite_kt ${KEYTAB_DIR}/hbase-krb5.keytab\nquit" | ktutil
printf "%b" "read_kt ${KEYTAB_DIR}/merged-krb5.keytab\nlist" | ktutil
printf "%b" "read_kt ${KEYTAB_DIR}/hbase-krb5.keytab\nlist" | ktutil
echo ""

echo "========== Changing permissions on Keytab files ==================================="
echo ""
chmod 444 ${KEYTAB_DIR}/hdfs.keytab
chmod 444 ${KEYTAB_DIR}/merged-krb5.keytab
chmod 444 ${KEYTAB_DIR}/http.hdfs.keytab
chmod 777 ${KEYTAB_DIR}/hbase-krb5.keytab
ls -lah ${KEYTAB_DIR}
echo ""

echo "========== KDC Server Configuration Successful ===================================="

/usr/bin/supervisord -c /etc/supervisord.conf -n