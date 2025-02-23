#!/bin/sh

set -e

# Check if there are any keytab files in the directory
if [ "$(ls -A /etc/security/keytabs/*.keytab 2>/dev/null)" ]; then
    echo "Keytabs found, will overwrite"
    ls -lah /etc/security/keytabs/
    echo "Removing existing keytabs from /etc/security/keytabs/"
    rm -f /etc/security/keytabs/*.keytab
else
    echo "No keytab files found in /etc/security/keytabs/"
fi

# Kerberos KDC server configuration
# Ref: https://github.com/dosvath/kerberos-containers/blob/master/kdc-server/init-script.sh

sed -i "s/realmValue/${REALM}/g" /var/lib/krb5kdc/kdc.conf
sed -i "s/realmValue/${REALM}/g" /etc/krb5.conf
sed -i "s/kdcserver/${MY_POD_NAME}.${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE}.svc.cluster.local/g" /etc/krb5.conf
sed -i "s/kdcadmin/${MY_POD_NAME}.${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE}.svc.cluster.local/g" /etc/krb5.conf

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

# Set variables
NAMENODE_FQDN=pegacorn-fhirplace-namenode-0.pegacorn-fhirplace-namenode.site-a.svc.cluster.local
DATANODE_ALPHA_FQDN=pegacorn-fhirplace-datanode-alpha-0.pegacorn-fhirplace-datanode-alpha.site-a.svc.cluster.local
DATANODE_BETA_FQDN=pegacorn-fhirplace-datanode-beta-0.pegacorn-fhirplace-datanode-beta.site-a.svc.cluster.local
SPNEGO_NAMENODE=pegacorn-fhirplace-namenode.site-a
SPNEGO_DATANODE_ALPHA=pegacorn-fhirplace-datanode-alpha.site-a
SPNEGO_DATANODE_BETA=pegacorn-fhirplace-datanode-beta.site-a
CLIENT_API_FQDN=pegacorn-fhirplace-bigdata-api-0.pegacorn-fhirplace-bigdata-api.site-a.svc.cluster.local

# Namenode Keytab
kadmin.local -q "add_principal -randkey  nn/${NAMENODE_FQDN}@${REALM}"
kadmin.local -q "ktadd -norandkey -k nn.service.keytab nn/${NAMENODE_FQDN}"
kadmin.local -q "add_principal -randkey  root/${NAMENODE_FQDN}@${REALM}"
kadmin.local -q "ktadd -norandkey -k nn.service.keytab root/${NAMENODE_FQDN}"

# Datanode alpha Keytab
kadmin.local -q "add_principal -randkey  dn/${DATANODE_ALPHA_FQDN}@${REALM}"
kadmin.local -q "ktadd -norandkey -k dna.service.keytab dn/${DATANODE_ALPHA_FQDN}"
kadmin.local -q "add_principal -randkey  root/${DATANODE_ALPHA_FQDN}@${REALM}"
kadmin.local -q "ktadd -norandkey -k dna.service.keytab root/${DATANODE_ALPHA_FQDN}"

# Datanode beta Keytab
kadmin.local -q "add_principal -randkey  bn/${DATANODE_BETA_FQDN}@${REALM}"
kadmin.local -q "ktadd -norandkey -k dnb.service.keytab bn/${DATANODE_BETA_FQDN}"
kadmin.local -q "add_principal -randkey  root/${DATANODE_BETA_FQDN}@${REALM}"
kadmin.local -q "ktadd -norandkey -k dnb.service.keytab root/${DATANODE_BETA_FQDN}"

# SPNEGO keytab for namenode service
kadmin.local -q "add_principal -randkey  HTTP/${SPNEGO_NAMENODE}@${REALM}"
kadmin.local -q "ktadd -norandkey -k http.service.keytab HTTP/${SPNEGO_NAMENODE}"

# SPNEGO keytab for datanode-alpha service
kadmin.local -q "add_principal -randkey  HTTP/${SPNEGO_DATANODE_ALPHA}@${REALM}"
kadmin.local -q "ktadd -norandkey -k http.service.keytab HTTP/${SPNEGO_DATANODE_ALPHA}"

# SPNEGO keytab for datanode-beta service
kadmin.local -q "add_principal -randkey  HTTP/${SPNEGO_DATANODE_BETA}@${REALM}"
kadmin.local -q "ktadd -norandkey -k http.service.keytab HTTP/${SPNEGO_DATANODE_BETA}"

# Local user keytab
kadmin.local -q "add_principal -randkey yemie@${REALM}"
kadmin.local -q "ktadd -norandkey -k user.service.keytab yemie"

# Client Keytab
kadmin.local -q "add_principal -randkey  fn/${CLIENT_API_FQDN}@${REALM}"
kadmin.local -q "ktadd -norandkey -k client.service.keytab fn/${CLIENT_API_FQDN}"
kadmin.local -q "add_principal -randkey  root/${CLIENT_API_FQDN}@${REALM}"
kadmin.local -q "ktadd -norandkey -k client.service.keytab root/${CLIENT_API_FQDN}"
echo ""

echo "==================================================================================="
echo "================ Moving keytab files to mount location ============================"
echo ""
mv nn.service.keytab ${KEYTAB_DIR}
mv dna.service.keytab ${KEYTAB_DIR}
mv dnb.service.keytab ${KEYTAB_DIR}
mv http.service.keytab ${KEYTAB_DIR}
mv user.service.keytab ${KEYTAB_DIR}
mv client.service.keytab ${KEYTAB_DIR}
ls -lah ${KEYTAB_DIR}

# echo "==================================================================================="
# echo "========== Merge Keytab files ======================"
# echo ""
# printf "%b" "read_kt ${KEYTAB_DIR}/hdfs.keytab\nread_kt ${KEYTAB_DIR}/http.hdfs.keytab\nwrite_kt ${KEYTAB_DIR}/merged-krb5.keytab\nquit" | ktutil
# printf "%b" "read_kt ${KEYTAB_DIR}/hdfs.keytab\nread_kt ${KEYTAB_DIR}/client.hdfs.keytab\nwrite_kt ${KEYTAB_DIR}/client-krb5.keytab\nquit" | ktutil

printf "%b" "read_kt ${KEYTAB_DIR}/nn.service.keytab\nlist" | ktutil
printf "%b" "read_kt ${KEYTAB_DIR}/dna.service.keytab\nlist" | ktutil
printf "%b" "read_kt ${KEYTAB_DIR}/dnb.service.keytab\nlist" | ktutil
printf "%b" "read_kt ${KEYTAB_DIR}/http.service.keytab\nlist" | ktutil
printf "%b" "read_kt ${KEYTAB_DIR}/user.service.keytab\nlist" | ktutil
printf "%b" "read_kt ${KEYTAB_DIR}/client.service.keytab\nlist" | ktutil
echo ""

echo "========== Changing permissions on Keytab files ==================================="
echo ""
chmod 444 ${KEYTAB_DIR}/nn.service.keytab
chmod 444 ${KEYTAB_DIR}/dna.service.keytab
chmod 444 ${KEYTAB_DIR}/dnb.service.keytab
chmod 444 ${KEYTAB_DIR}/http.service.keytab
chmod 444 ${KEYTAB_DIR}/user.service.keytab
chmod 444 ${KEYTAB_DIR}/client.service.keytab
ls -lah ${KEYTAB_DIR}
echo ""

echo "========== KDC Server Configuration Successful ===================================="

/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf -n