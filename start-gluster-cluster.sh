#!/bin/bash
set -ue
BIN_DIR="$(dirname "$0")"

# Number of glusterfs bricks in cluster.
NUMBER_OF_BRICKS="${1:?ERROR: Argument is required: number of bricks to start, e.g. 3.}"

# Number of replicas: 2 - any 1 node can be out of cluster, 3 - any 2 nodes can be out cluster.
REPLICAS="${2:?ERROR: Argument is required: number of replicas of files to create, e.g. 2. Each replica will increase faultolerance but will divide bandwith.}"

CLUSTER_DRIVER="$BIN_DIR/cluster-docker.sh"

(( NUMBER_OF_BRICKS % REPLICAS == 0 )) || {
  echo "ERROR: Number of bricks is not a multiple of replica count. Number of peers must be $(( (NUMBER_OF_BRICKS/REPLICAS)*REPLICAS )) or $(( (NUMBER_OF_BRICKS/REPLICAS)*REPLICAS+REPLICAS ))." >&2
  exit 1
}


# Unmount gluster filesystem used for testing, if any.
sudo umount -f "$HOME/tmp/gluster" || :
# Unmount nfs filesystem used for testing, if any.
sudo umount -f "$HOME/tmp/nfs" || :

#
# (Re)start cluster
#
restart_cluster() {
"$CLUSTER_DRIVER" stop "$NUMBER_OF_BRICKS" || :
"$CLUSTER_DRIVER" run "$NUMBER_OF_BRICKS"
}

#
# Get IP's of cluster nodes.
# NOTE: Use flannel for networking, so hosts will be accessible directly.
#
get_ip_addresses_of_nodes() {
  IP_ADDRESSES=( )
  MAP=""
  NODES=( )
  for((I=1; I<=NUMBER_OF_BRICKS; I++))
  do
    local IP="$("$CLUSTER_DRIVER" ip_of_one "$I")"
    IP_ADDRESSES+=( "$IP" )
    MAP="$MAP$IP node$I"$'\n'
    NODES+=( "node$I" )
  done

  echo "MAP: $MAP"

  for((I=1; I<=NUMBER_OF_BRICKS; I++))
  do
    a bash -c "echo '$MAP' >>/etc/hosts"
  done

  IP_OF_MASTER="${IP_ADDRESSES[0]}"
  MASTER="${NODES[0]}"
  PEERS=( "${NODES[@]:1}" )

  echo "INFO: All IP Adresses: ${IP_ADDRESSES[*]}"
  echo "INFO: Master server: $MASTER ($IP_OF_MASTER)"
  echo "INFO: Peers: ${PEERS[@]}"
}

#
# Helper functions
#

# Exec command on master node
m() {
  echo "INFO: Executing on master: $*"
  "$CLUSTER_DRIVER" exec_one 1 "$@"
}

# Exec command on all nodes
a() {
  echo "INFO: Executing on all: $*"
  "$CLUSTER_DRIVER" exec "$NUMBER_OF_BRICKS" "$@"
}

#
# Joint Gluster bricks to trusted pool
#
join_bricks_to_trusted_pool() {
  for PEER in "${PEERS[@]}"
  do
    # Probe peers (join them to trusted pool).
    m gluster peer probe "$PEER"
  done
  # Note: When using hostnames, the first server needs to be probed from one other server to set its hostname.

  # Wait until peers will join
  sleep 4

  # Check status of peers (optional)
  m gluster peer status
}

#
# Setup Gluster volume
#
setup_gluster_volume() {
  # Create directory to store data. It should be on separate device formatted with ext4 or xfs.
  a mkdir -p "/exports/shared"

  # Create volume "shared" with two copies of each file. "Force" is necessary to create volume on root filesystem.
  # TODO: test replicated-distributed setup.
  # TODO: mount a sparse looop file to each file, for persistent storage of data and for support of discard option.
  m gluster volume create shared replica "$REPLICAS" transport tcp "${IP_ADDRESSES[@]/%/:/exports/shared}" force

  #m gluster volume create shared replica "$REPLICAS" transport tcp "${IP_ADDRESSES[@]/%/:/exports/shared}" force || {
  #  # Allow user to continue, in case of timeout, when volume will be ready to start.
  #  # Request timeout occurs when large number of nodes is added, when they all are on same PC.
  #  while ! ( m gluster volume info | grep -q 'Volume Name: shared' )
  #  do
  #    m gluster volume info
  #    sleep 10
  #    done
  #  m gluster volume info
  #}

  # Start volume "shared"
  m gluster volume start shared
}

#
# Setup nfs-ganesha
#
setup_nfs_ganesha() {
# Mount volume "shared" on bricks for nfs-ganesha to work
#a mkdir -p "/shared"
#a mount -t glusterfs "$MASTER:/shared" "/shared"

# Enable parallel NFS
m bash -c "echo 'GLUSTER { PNFS_MDS = true; }' >> /etc/ganesha/ganesha.conf"
m gluster volume set shared features.cache-invalidation on
# After 'timeout' seconds since the time client accessed any file, cache-invalidation notifications are no longer sent to that client.
# Default value: 60 seconds.
m gluster volume set shared features.cache-invalidation-timeout 300

# Disable gluster built-in NFS in favor of nfs-ganesha
a gluster volume set shared nfs.disable on

# Enable nfs-ganesha feature
a mkdir -p /var/run/gluster/shared_storage/
m gluster nfs-ganesha enable --mode=script

# Export /shared volume via ganesha
m gluster volume set shared ganesha.enable on

# Restart nfs-ganesha service to pickup changes
a systemctl restart nfs-ganesha

# Wait until nfs-ganesha will start
sleep 30

# Check is configuration is exported via nfs
m gluster volume info
m showmount -e
}

#
# Mount Gluster and NFS for testing
#
mount_gluster_for_testing() {
 # Mount shared volume via gluster on host for testing
  echo "INFO: Mounting glusterfs from \"$IP_OF_MASTER:/shared\" to \"$HOME/tmp/gluster\"."
  mkdir -p "$HOME/tmp/gluster"
  sudo mount -t glusterfs "$IP_OF_MASTER:/shared" "$HOME/tmp/gluster"
}
mount_nfs_for_testing() {
  # Mount shared volume via nfs on host for testing
  echo "INFO: Mounting NFS 4.1 from \"$IP_OF_MASTER:/shared\" to \"$HOME/tmp/nfs\"."
  mkdir -p "$HOME/tmp/nfs"
  sudo mount -t nfs -o vers=4.1,proto=tcp "$IP_OF_MASTER:/shared" "$HOME/tmp/nfs"
}

[ "${SKIP_RESTART:-no}" == "yes" ] || restart_cluster || {
  echo "ERROR: Cannot restart cluster." >&2
  exit 1
}

get_ip_addresses_of_nodes || {
  echo "ERROR: Cannot get IP addresses of nodes." >&2
  exit 1
}

[ "${SKIP_JOIN:-no}" == "yes" ] || join_bricks_to_trusted_pool || {
  echo "ERROR: Cannot join glusterfs bricks to trusted pool." >&2
  exit 1
}

[ "${SKIP_SETUP_VOLUME:-no}" == "yes" ] || setup_gluster_volume || {
  echo "ERROR: Cannot setup gluster volume." >&2
  exit 1
}

[ "${SKIP_SETUP_NFS:-no}" == "yes" ] || setup_nfs_ganesha || {
  echo "ERROR: Cannot setup nfs ganesha." >&2
  exit 1
}

[ "${SKIP_MOUNT_GLUSTER:-no}" == "yes" ] || mount_gluster_for_testing || {
  echo "ERROR: Cannot mount glusterfs for testing." >&2
  exit 1
}

[ "${SKIP_MOUNT_NFS:-no}" == "yes" ] || mount_nfs_for_testing || {
  echo "ERROR: Cannot mount nfs for testing." >&2
  exit 1
}
