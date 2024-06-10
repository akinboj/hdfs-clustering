#!/bin/bash

set -e

if [ -f "/hadoop/dfs/datanode/in_use.lock" ]; then
echo "removing existing filelock : /hadoop/dfs/datanode/in_use.lock"
rm -f /hadoop/dfs/datanode/in_use.lock
fi

# kerberos client
sed -i "s/realmValue/${REALM}/g" /etc/krb5.conf
sed -i "s/kdcserver/pegacorn-fhirplace-kdcserver-0.pegacorn-fhirplace-kdcserver.site-a/g" /etc/krb5.conf
sed -i "s/kdcadmin/pegacorn-fhirplace-kdcserver-0.pegacorn-fhirplace-kdcserver.site-a/g" /etc/krb5.conf

echo "==== Authenticating to realm ==============================================================="
echo "============================================================================================"
KRB5_TRACE=/dev/stderr kinit -f dnb/pegacorn-fhirplace-datanode-beta-0.pegacorn-fhirplace-datanode-beta.site-a.svc.cluster.local@${REALM} -kt ${KEYTAB_DIR}/merged-krb5.keytab -V &
wait -n
echo "Datanode-beta TGT completed."
echo ""

# Copy the root CA certificate to the container
cp ${CERTS}/ca.cer /usr/local/share/ca-certificates/ca.crt

# Update the trusted certificate store
apt-get update && \
apt-get install -y ca-certificates && \
update-ca-certificates && \
rm -rf /var/lib/apt/lists/*

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
    addProperty /etc/hadoop/core-site.xml fs.defaultFS hdfs://${NAMENODE_HOST}:8020
    # Enable Kerberos Authentication
    addProperty /etc/hadoop/core-site.xml hadoop.security.authentication kerberos
    addProperty /etc/hadoop/core-site.xml hadoop.security.authorization false
    # Specify the Kerberos Principal for HTTP access
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.kerberos.principal HTTP/pegacorn-fhirplace-namenode-0.pegacorn-fhirplace-namenode.site-a.svc.cluster.local@${REALM}
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.kerberos.keytab ${KEYTAB_DIR}/merged-krb5.keytab
    # Enable HTTPS and configure related settings
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.server.conf ssl-server.xml
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.client.conf ssl-client.xml
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.keystores.factory.class org.apache.hadoop.security.ssl.FileBasedKeyStoresFactory
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.type kerberos
    addProperty /etc/hadoop/core-site.xml hadoop.http.filter.initializers org.apache.hadoop.security.AuthenticationFilterInitializer,org.apache.hadoop.security.HttpCrossOriginFilterInitializer
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.token.validity 36000
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.cookie.domain ${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE}
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.cookie.persistent false
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.require.client.cert false
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.hostname.verifier ALLOW_ALL
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.signature.secret.file ${CERTS}/hadoop-http-auth-signature-secret
    # RPC Protection (Data transfer protection)
    addProperty /etc/hadoop/core-site.xml hadoop.rpc.protection privacy
    # Other settings
    addProperty /etc/hadoop/core-site.xml hadoop.user.group.static.mapping.overrides HTTP/pegacorn-fhirplace-namenode-0.pegacorn-fhirplace-namenode.site-a.svc.cluster.local@${REALM}=pegacorn
    addProperty /etc/hadoop/core-site.xml hadoop.security.auth_to_local "RULE:[1:$1@$0](.*@PEGACORN-FHIRPLACE-AUDIT.LOCAL)s/.*$/jboss/ DEFAULT"

    # HDFS
    addProperty /etc/hadoop/hdfs-site.xml dfs.replication 1
    addProperty /etc/hadoop/hdfs-site.xml dfs.permissions.superusergroup jboss
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.kerberos.principal dnb/_HOST@${REALM}
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.keytab.file ${KEYTAB_DIR}/merged-krb5.keytab
    addProperty /etc/hadoop/hdfs-site.xml dfs.block.access.token.enable true
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.address ${MY_POD_IP}:9866
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.https.address ${MY_POD_IP}:9865
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.ipc.address ${MY_POD_IP}:9867
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.https-address ${NAMENODE_HOST}:9871
    addProperty /etc/hadoop/hdfs-site.xml dfs.http.policy HTTPS_ONLY
    addProperty /etc/hadoop/hdfs-site.xml dfs.server.https.keystore.resource ssl-server.xml
    addProperty /etc/hadoop/hdfs-site.xml dfs.client.https.keystore.resource ssl-client.xml
    addProperty /etc/hadoop/hdfs-site.xml dfs.client.https.need-auth false
    addProperty /etc/hadoop/hdfs-site.xml dfs.encrypt.data.transfer true
    addProperty /etc/hadoop/hdfs-site.xml dfs.client.use.datanode.hostname false
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.use.datanode.hostname false
    addProperty /etc/hadoop/hdfs-site.xml dfs.data.transfer.protection privacy
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.kerberos.internal.spnego.principal HTTP/pegacorn-fhirplace-namenode-0.pegacorn-fhirplace-namenode.site-a.svc.cluster.local@${REALM}
    addProperty /etc/hadoop/hdfs-site.xml dfs.web.authentication.kerberos.principal HTTP/pegacorn-fhirplace-namenode-0.pegacorn-fhirplace-namenode.site-a.svc.cluster.local@${REALM}
    addProperty /etc/hadoop/hdfs-site.xml dfs.web.authentication.kerberos.keytab ${KEYTAB_DIR}/merged-krb5.keytab
fi


datadir=`echo $HDFS_CONF_dfs_datanode_data_dir | perl -pe 's#file://##'`
if [ ! -d $datadir ]; then
  echo "Datanode data directory not found: $datadir"
  exit 2
fi

$HADOOP_HOME/bin/hdfs --config $HADOOP_CONF_DIR datanode