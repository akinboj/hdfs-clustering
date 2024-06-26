#!/bin/bash

set -e

echo "==== Check lock file ==============================================================="
echo "===================================================================================="
# Manage lock when pod restarts
if [ "$(ls -A /hadoop/dfs/namenode/*.lock 2>/dev/null)" ]; then
    echo "Lockfile found, will overwrite"
    ls -lah /hadoop/dfs/namenode/
    echo "Removing existing lockfile from /hadoop/dfs/namenode/"
    rm -f /hadoop/dfs/namenode/*.lock
else
    echo "No lock file found in /hadoop/dfs/namenode/"
fi
echo ""

# kerberos client
# echo ${MY_POD_IP} ${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE} >> /etc/hosts
sed -i "s/realmValue/${REALM}/g" /etc/krb5.conf
sed -i "s/kdcserver/pegacorn-fhirplace-kdcserver-0.pegacorn-fhirplace-kdcserver.site-a.svc.cluster.local/g" /etc/krb5.conf
sed -i "s/kdcadmin/pegacorn-fhirplace-kdcserver-0.pegacorn-fhirplace-kdcserver.site-a.svc.cluster.local/g" /etc/krb5.conf

# Copy the root CA certificate to the container
cp ${CERTS}/ca.cer /usr/local/share/ca-certificates/ca.crt

# Update the trusted certificate store
apt-get update && \
apt-get install -y ca-certificates && \
update-ca-certificates && \
rm -rf /var/lib/apt/lists/*

# Create http signature file
openssl rand -base64 256 > ${CERTS}/hadoop-http-auth-signature-secret

echo ""
echo "==== Authenticating to realm ==============================================================="
echo "============================================================================================"
KRB5_TRACE=/dev/stderr kinit -f nn/${SERVER_ADDRESS}@${REALM} -kt ${KEYTAB_DIR}/nn.service.keytab -V &
wait -n
echo "NameNode TGT completed."
echo ""

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
    addProperty /etc/hadoop/core-site.xml fs.defaultFS hdfs://${SERVER_ADDRESS}:8020
    # Enable Kerberos Authentication
    addProperty /etc/hadoop/core-site.xml hadoop.security.authentication kerberos
    addProperty /etc/hadoop/core-site.xml hadoop.security.authorization true
    # Specify the Kerberos Principal for HTTP access
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.kerberos.principal HTTP/_HOST@${REALM}
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.kerberos.keytab ${KEYTAB_DIR}/http.service.keytab
    # Enable HTTPS and configure related settings
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.server.conf ssl-server.xml
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.client.conf ssl-client.xml
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.keystores.factory.class org.apache.hadoop.security.ssl.FileBasedKeyStoresFactory
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.type kerberos
    addProperty /etc/hadoop/core-site.xml hadoop.http.filter.initializers org.apache.hadoop.security.AuthenticationFilterInitializer,org.apache.hadoop.security.HttpCrossOriginFilterInitializer
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.token.validity 36000
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.cookie.domain ${KUBERNETES_SERVICE_NAME}.${KUBERNETES_NAMESPACE}
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.cookie.persistent true
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.require.client.cert false
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.hostname.verifier ALLOW_ALL
    addProperty /etc/hadoop/core-site.xml hadoop.http.cross-origin.enabled true
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.signature.secret.file ${CERTS}/hadoop-http-auth-signature-secret
    # RPC Protection (Data transfer protection)
    addProperty /etc/hadoop/core-site.xml hadoop.rpc.protection privacy
    # View file system
    addProperty /etc/hadoop/core-site.xml fs.viewfs.overload.scheme.target.hdfs.impl org.apache.hadoop.hdfs.DistributedFileSystem
    # Other settings
    addProperty /etc/hadoop/core-site.xml hadoop.http.staticuser.user	root
    addProperty /etc/hadoop/core-site.xml hadoop.security.auth_to_local 'RULE:[2:$1/$2@$0]([ndbf]n/.*@REALM.TLD)s/.*/root/'

    # HDFS
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.rpc-bind-host ${SERVER_ADDRESS}
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.servicerpc-bind-host ${SERVER_ADDRESS}
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.https-bind-host ${SERVER_ADDRESS}
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.datanode.registration.ip-hostname-check false
    addProperty /etc/hadoop/hdfs-site.xml dfs.client.use.datanode.hostname true
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.use.datanode.hostname true
    addProperty /etc/hadoop/hdfs-site.xml dfs.encrypt.data.transfer true
    addProperty /etc/hadoop/hdfs-site.xml dfs.block.access.token.enable true
    addProperty /etc/hadoop/hdfs-site.xml dfs.replication 1
    addProperty /etc/hadoop/hdfs-site.xml dfs.cluster.administrators *
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.address 0.0.0.0:9866
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.https.address 0.0.0.0:9865
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.ipc.address 0.0.0.0:9867
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.https-address ${SERVER_ADDRESS}:9871
    addProperty /etc/hadoop/hdfs-site.xml dfs.client.https.need-auth false
    addProperty /etc/hadoop/hdfs-site.xml dfs.data.transfer.protection privacy
    addProperty /etc/hadoop/hdfs-site.xml dfs.http.policy HTTPS_ONLY
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.kerberos.principal nn/_HOST@${REALM}
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.keytab.file ${KEYTAB_DIR}/nn.service.keytab
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.kerberos.internal.spnego.principal HTTP/_HOST@${REALM}
    addProperty /etc/hadoop/hdfs-site.xml dfs.web.authentication.kerberos.principal HTTP/_HOST@${REALM}
    addProperty /etc/hadoop/hdfs-site.xml dfs.web.authentication.kerberos.keytab ${KEYTAB_DIR}/http.service.keytab
fi

function wait_for_it()
{
    local serviceport=$1
    local service=${serviceport%%:*}
    local port=${serviceport#*:}
    local retry_seconds=5
    local max_try=100
    let i=1

    nc -z $service $port
    result=$?

    until [ $result -eq 0 ]; do
      echo "[$i/$max_try] check for ${service}:${port}..."
      echo "[$i/$max_try] ${service}:${port} is not available yet"
      if (( $i == $max_try )); then
        echo "[$i/$max_try] ${service}:${port} is still not available; giving up after ${max_try} tries. :/"
        exit 1
      fi
      
      echo "[$i/$max_try] try in ${retry_seconds}s once again ..."
      let "i++"
      sleep $retry_seconds

      nc -z $service $port
      result=$?
    done
    echo "[$i/$max_try] $service:${port} is available."
}

for i in ${SERVICE_PRECONDITION[@]}
do
    wait_for_it ${i}
done

### End entrypoint.sh

namedir=`echo $HDFS_CONF_dfs_namenode_name_dir | perl -pe 's#file://##'`
if [ ! -d $namedir ]; then
  echo "Namenode name directory not found: $namedir"
  exit 2
fi

if [ -z "$CLUSTER_NAME" ]; then
  echo "Cluster name not specified"
  exit 2
fi

if [ "`ls -A $namedir`" == "" ]; then
  echo "Formatting namenode name directory: $namedir"
  $HADOOP_HOME/bin/hdfs --config $HADOOP_CONF_DIR namenode -format $CLUSTER_NAME
fi

$HADOOP_HOME/bin/hdfs --config $HADOOP_CONF_DIR namenode