#!/bin/bash

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

echo "==== Configuring Kerberos KDC Server ==============================================="
echo "==================================================================================="

# Kerberos KDC server configuration
sed -i "s/realmValue/${REALM}/g" /var/lib/krb5kdc/kdc.conf
sed -i "s/realmValue/${REALM}/g" /etc/krb5.conf
sed -i "s/kdcserver/${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE}.svc.cluster.local/g" /etc/krb5.conf
sed -i "s/kdcadmin/${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE}.svc.cluster.local/g" /etc/krb5.conf

echo "==== Creating Kerberos Realm ======================================================"
echo "==================================================================================="
KADMIN_PRINCIPAL=root/admin
KADMIN_PRINCIPAL_FULL=$KADMIN_PRINCIPAL@$REALM
MASTER_PASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1)
CLIENT_API_FQDN=pegacorn-fhirplace-bigdata-api.site-a.svc.cluster.local
LOCAL_USER=yemie # Change to your local user account name

kdb5_util create -r "$REALM" -s -P ${MASTER_PASSWORD}
echo ""

echo "==== Creating Kerberos Admin Account =============================================="
echo "==================================================================================="
echo "Adding Kerberos Admin Principal: ${KADMIN_PRINCIPAL_FULL}"
kadmin.local -q "addprinc -pw ${MASTER_PASSWORD} ${KADMIN_PRINCIPAL_FULL}"
echo ""

echo "==== Generating Admin Keytab ======================================================"
echo "==================================================================================="
kadmin.local -q "ktadd -k ${KEYTAB_DIR}/admin.keytab ${KADMIN_PRINCIPAL_FULL}"
chmod 600 ${KEYTAB_DIR}/admin.keytab
echo "Admin keytab created at ${KEYTAB_DIR}/admin.keytab"
echo ""

echo "==== Generating Client Keytabs ======================================================"
echo "==================================================================================="
# Local user keytab
kadmin.local -q "add_principal -randkey ${LOCAL_USER}@${REALM}"
kadmin.local -q "ktadd -norandkey -k ${KEYTAB_DIR}/user.service.keytab ${LOCAL_USER}"

# Client Keytab
kadmin.local -q "add_principal -randkey  fn/${CLIENT_API_FQDN}@${REALM}"
kadmin.local -q "ktadd -norandkey -k ${KEYTAB_DIR}/client.service.keytab fn/${CLIENT_API_FQDN}"
chmod 600 ${KEYTAB_DIR}/user.service.keytab
chmod 600 ${KEYTAB_DIR}/client.service.keytab
echo ""

# Verify principals exist
echo "==== Service Principals created ==================================================="
echo "==================================================================================="
kadmin.local -q "listprincs"
echo ""

ls -lah ${KEYTAB_DIR}
printf "%b" "read_kt ${KEYTAB_DIR}/admin.keytab\nlist" | ktutil
printf "%b" "read_kt ${KEYTAB_DIR}/user.service.keytab\nlist" | ktutil
printf "%b" "read_kt ${KEYTAB_DIR}/client.service.keytab\nlist" | ktutil

echo "==== KDC Server Configuration Successful =========================================="
echo "==================================================================================="

# Start Kerberos KDC and Kadmin services in the foreground
krb5kdc -n &
kadmind -nofork &
wait -n