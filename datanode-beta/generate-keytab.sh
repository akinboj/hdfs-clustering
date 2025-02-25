#!/bin/bash

set -e

# Set KDC server
KDC_SERVER=pegacorn-fhirplace-kdcserver.site-a.svc.cluster.local

# Update Kerberos configuration dynamically
sed -i "s/realmValue/${REALM}/g" /etc/krb5.conf
sed -i "s/kdcserver/${KDC_SERVER}/g" /etc/krb5.conf
sed -i "s/kdcadmin/${KDC_SERVER}/g" /etc/krb5.conf

echo "Starting keytab generation..."

# Ensure MY_POD_NAME is set
if [ -z "${MY_POD_NAME}" ]; then
    echo "ERROR: MY_POD_NAME is not set. Exiting."
    exit 1
fi

# Set service principals
NAMENODE_PRINCIPAL="bn/${MY_POD_NAME}@${REALM}"
HTTP_PRINCIPAL="HTTP/${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE}@${REALM}"

# Function to create principal if it does not exist
function create_principal_if_not_exists() {
    local principal=$1
    echo "Checking if principal ${principal} exists..."
    
    if kadmin -p root/admin -kt ${ADMIN_KEYTAB_DIR}/admin.keytab -q "get_principal ${principal}" 2>&1 | grep -q "Principal does not exist"; then
        echo "Principal ${principal} does NOT exist. Creating it..."
        kadmin -p root/admin -kt ${ADMIN_KEYTAB_DIR}/admin.keytab -q "add_principal -randkey ${principal}"
    else
        echo "Principal ${principal} already exists."
    fi
}

# Function to generate keytab if it does not exist
function generate_keytab_if_not_exists() {
    local principal=$1
    local keytab=$2

    if [ ! -f ${keytab} ]; then
        echo "Generating keytab for ${principal}..."
        if ! kadmin -p root/admin -kt ${ADMIN_KEYTAB_DIR}/admin.keytab -q "ktadd -k ${keytab} ${principal}"; then
            echo "ERROR: Failed to generate keytab for ${principal}"
            exit 1
        fi
    else
        echo "Keytab for ${principal} already exists. Skipping."
    fi
}

# Create and generate keytabs
create_principal_if_not_exists "${NAMENODE_PRINCIPAL}"
generate_keytab_if_not_exists "${NAMENODE_PRINCIPAL}" "${HDFS_KEYTAB_DIR}/dnb.service.keytab"

create_principal_if_not_exists "${HTTP_PRINCIPAL}"
generate_keytab_if_not_exists "${HTTP_PRINCIPAL}" "${HDFS_KEYTAB_DIR}/http.service.keytab"

# Set secure permissions on keytabs
chmod 600 ${HDFS_KEYTAB_DIR}/dnb.service.keytab
chmod 600 ${HDFS_KEYTAB_DIR}/http.service.keytab

ls -lah ${HDFS_KEYTAB_DIR}
printf "%b" "read_kt ${HDFS_KEYTAB_DIR}/dnb.service.keytab\nlist" | ktutil
printf "%b" "read_kt ${HDFS_KEYTAB_DIR}/http.service.keytab\nlist" | ktutil

echo ""
echo "Keytab generation complete. Keeping container running..."
sleep infinity  # Keep sidecar running to maintain shared volume
