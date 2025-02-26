#!/bin/bash

set -e

echo "==== Check lock file ==============================================================="
echo "===================================================================================="
# Manage lock when pod restarts
if [ "$(ls -A /hadoop/dfs/datanode/*.lock 2>/dev/null)" ]; then
    echo "Lockfile found, will overwrite"
    ls -lah /hadoop/dfs/datanode/
    echo "Removing existing lockfile from /hadoop/dfs/datanode/"
    rm -f /hadoop/dfs/datanode/*.lock
else
    echo "No lock file found in /hadoop/dfs/datanode/"
fi
echo ""

# Set KDC server
KDC_SERVER=pegacorn-fhirplace-kdcserver.site-a.svc.cluster.local

# Update Kerberos configuration dynamically
sed -i "s/realmValue/${REALM}/g" /etc/krb5.conf
sed -i "s/kdcserver/${KDC_SERVER}/g" /etc/krb5.conf
sed -i "s/kdcadmin/${KDC_SERVER}/g" /etc/krb5.conf

# Copy the root CA certificate to the container
cp ${CERTS}/ca.cer /usr/local/share/ca-certificates/ca.crt

# Update the trusted certificate store
apk add --no-cache ca-certificates
update-ca-certificates

# Create HTTP signature file
openssl rand -base64 256 > ${CERTS}/hadoop-http-auth-signature-secret

echo ""
echo "==== Waiting for keytab to be available ============================================"
echo "===================================================================================="
# Ensure the keytab is generated by the sidecar before proceeding
while [ ! -f ${HDFS_KEYTAB_DIR}/dna.service.keytab ]; do
    echo "Waiting for datanode keytab..."
    sleep 2
done

while [ ! -f ${HDFS_KEYTAB_DIR}/http.service.keytab ]; do
    echo "Waiting for HTTP keytab..."
    sleep 2
done

echo "Keytabs are ready. Proceeding with Kerberos authentication..."
echo ""

echo ""
echo "==== Authenticating Datanode to Kerberos Realm ====================================="
echo "===================================================================================="
export KRB5CCNAME=/tmp/krb5cc_nn
KRB5_TRACE=/dev/stderr kinit -f dn/${MY_POD_NAME}@${REALM} -kt ${HDFS_KEYTAB_DIR}/dna.service.keytab -V &
wait -n
echo "Datanode-Alpha TGT completed."
echo ""

echo ""
echo "==== Authenticating HTTP Service to Kerberos Realm ================================="
echo "===================================================================================="
export KRB5CCNAME=/tmp/krb5cc_http
KRB5_TRACE=/dev/stderr kinit -f HTTP/${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE}@${REALM} -kt ${HDFS_KEYTAB_DIR}/http.service.keytab -V &
wait -n
echo "HTTP TGT completed."
echo ""

echo 'export KRB5CCNAME=/tmp/krb5cc_nn' >> /etc/profile
echo 'export KRB5CCNAME=/tmp/krb5cc_nn' >> ~/.bashrc
source ~/.bashrc

### Start entrypoint.sh
### https://github.com/big-data-europe/docker-hadoop/blob/master/base/entrypoint.sh
function addProperty() {
  local path=$1
  local name=$2
  local value=$3

  local entry="<property><name>$name</name><value>${value}</value></property>"
  local escapedEntry=$(echo $entry | sed 's/\//\\\//g')
  sed -i "/<\/configuration>/ s/.*/${escapedEntry}\n&/" $path
}

function configure() {
    local path=$1
    local module=$2
    local envPrefix=$3

    local var
    local value
    
    echo "Configuring $module"
    for c in `printenv | perl -sne 'print "$1 " if m/^${envPrefix}_(.+?)=.*/' -- -envPrefix=$envPrefix`; do 
        name=`echo ${c} | perl -pe 's/___/-/g; s/__/@/g; s/_/./g; s/@/_/g;'`
        var="${envPrefix}_${c}"
        value=${!var}
        echo " - Setting $name=$value"
        addProperty $path $name "$value"
    done
}

configure /etc/hadoop/core-site.xml core CORE_CONF
configure /etc/hadoop/hdfs-site.xml hdfs HDFS_CONF

if [ "$MULTIHOMED_NETWORK" = "1" ]; then
    echo "Configuring for multihomed network"

    # CORE (This will be same on Datanodes to ensure consistency across the cluster)
    # Define the FileSystem URI
    addProperty /etc/hadoop/core-site.xml fs.defaultFS hdfs://${NAMENODE_HOST}:32412
    # Enable Kerberos Authentication
    addProperty /etc/hadoop/core-site.xml hadoop.security.authentication kerberos
    addProperty /etc/hadoop/core-site.xml hadoop.security.authorization true
    # Specify the Kerberos Principal for HTTP access
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.kerberos.principal HTTP/${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE}@${REALM}
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.kerberos.keytab ${HDFS_KEYTAB_DIR}/http.service.keytab
    # Enable HTTPS and configure related settings
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.server.conf ssl-server.xml
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.client.conf ssl-client.xml
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.keystores.factory.class org.apache.hadoop.security.ssl.FileBasedKeyStoresFactory
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.type kerberos
    addProperty /etc/hadoop/core-site.xml hadoop.http.filter.initializers org.apache.hadoop.security.AuthenticationFilterInitializer,org.apache.hadoop.security.HttpCrossOriginFilterInitializer
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.token.validity 36000
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.cookie.domain ${KUBERNETES_NAMESPACE}
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.require.client.cert false
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.hostname.verifier ALLOW_ALL
    addProperty /etc/hadoop/core-site.xml hadoop.http.cross-origin.enabled true
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.signature.secret.file ${CERTS}/hadoop-http-auth-signature-secret
    # RPC Protection (Data transfer protection)
    addProperty /etc/hadoop/core-site.xml hadoop.rpc.protection privacy
    # View file system
    addProperty /etc/hadoop/core-site.xml fs.viewfs.overload.scheme.target.hdfs.impl org.apache.hadoop.hdfs.DistributedFileSystem
    # Other settings
    addProperty /etc/hadoop/core-site.xml hadoop.http.staticuser.user root
    addProperty /etc/hadoop/core-site.xml hadoop.security.auth_to_local 'RULE:[2:$1/$2@$0]([ndbf]n/.*@REALM.TLD)s/.*/root/ RULE:[2:$1/$2@$0](HTTP/.*@REALM.TLD)s/.*/root/ DEFAULT'

    # HDFS
    addProperty /etc/hadoop/hdfs-site.xml dfs.replication 2
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.kerberos.principal dn/_HOST@${REALM}
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.keytab.file ${HDFS_KEYTAB_DIR}/dna.service.keytab
    addProperty /etc/hadoop/hdfs-site.xml dfs.block.access.token.enable true
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.address ${MY_POD_NAME}:9866
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.https.address ${MY_POD_NAME}:9865
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.ipc.address ${MY_POD_NAME}:9867
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.https-address ${NAMENODE_HOST}:32410
    addProperty /etc/hadoop/hdfs-site.xml dfs.http.policy HTTPS_ONLY
    addProperty /etc/hadoop/hdfs-site.xml dfs.server.https.keystore.resource ssl-server.xml
    addProperty /etc/hadoop/hdfs-site.xml dfs.client.https.keystore.resource ssl-client.xml
    addProperty /etc/hadoop/hdfs-site.xml dfs.client.https.need-auth false
    addProperty /etc/hadoop/hdfs-site.xml dfs.encrypt.data.transfer true
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.datanode.registration.ip-hostname-check false
    addProperty /etc/hadoop/hdfs-site.xml dfs.client.use.datanode.hostname false
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.use.datanode.hostname false
    addProperty /etc/hadoop/hdfs-site.xml dfs.cluster.administrators '*'
    addProperty /etc/hadoop/hdfs-site.xml dfs.permissions.superusergroup supergroup
    addProperty /etc/hadoop/hdfs-site.xml dfs.data.transfer.protection privacy
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.kerberos.internal.spnego.principal HTTP/${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE}@${REALM}
    addProperty /etc/hadoop/hdfs-site.xml dfs.web.authentication.kerberos.principal HTTP/${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE}@${REALM}
    addProperty /etc/hadoop/hdfs-site.xml dfs.web.authentication.kerberos.keytab ${HDFS_KEYTAB_DIR}/http.service.keytab
fi


datadir=`echo $HDFS_CONF_dfs_datanode_data_dir | perl -pe 's#file://##'`
if [ ! -d $datadir ]; then
  echo "Datanode data directory not found: $datadir"
  exit 2
fi

$HADOOP_HOME/bin/hdfs --config $HADOOP_CONF_DIR datanode