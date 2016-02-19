#!/bin/bash
set -ue
BIN_DIR="$(dirname "$0")"

# Number of glusterfs bricks in cluster.
NUM=3

# Unmount gluster filesystem used for testing, if any.
sudo umount "$HOME/tmp/gluster" || :
# Unmount nfs filesystem used for testing, if any.
sudo umount "$HOME/tmp/nfs" || :

"$BIN_DIR"/cluster.sh stop $NUM || :
"$BIN_DIR"/cluster.sh run $NUM

IP_ADDRESSES=( )
for((I=1; I<=NUM; I++))
do
  IP_ADDRESSES+=( "$("$BIN_DIR"/cluster.sh ip_of_one "$I")" )
done

echo "INFO: IP Adresses: ${IP_ADDRESSES[*]}"

IP_OF_MASTER="${IP_ADDRESSES[0]}"
IP_OF_PEERS=( "${IP_ADDRESSES[@]:1}" )

echo "INFO: Master server: $IP_OF_MASTER"
echo "INFO: Peers: ${IP_OF_PEERS[@]}"

# Exec command on master node
m() {
  echo "INFO: Executing on master: $*"
  "$BIN_DIR"/cluster.sh exec_one 1 "$@"
}
# Exec command on all nodes
a() {
  echo "INFO: Executing on all: $*"
  "$BIN_DIR"/cluster.sh exec $NUM "$@"
}

for IP in "${IP_OF_PEERS[@]}"
do
  # Probe peers (join them to trusted pool).
  m gluster peer probe "$IP"
done

# Wait until peers will join
sleep 3

# Check status of peers
m gluster peer status

# Create directory to store data. It should be on separate device formatted with ext4 or xfs.
a mkdir -p "/exports/shared"

# Create volume "shared" with two copies of each file. "Force" is necessary to create volume on root filesystem.
m gluster volume create shared replica 2 transport tcp "${IP_OF_PEERS[@]/%/:/exports/shared}" force

# Start volume "shared"
m gluster volume start shared

# Mount volume "shared" on bricks for nfs-ganesha to work
a mkdir -p "/shared"
a mount -t glusterfs "$IP_OF_MASTER:/shared" "/shared"

# Enable parallel NFS
m bash -c "echo 'GLUSTER { PNFS_MDS = true; }' >> /etc/ganesha/ganesha.conf"
m gluster vol set shared features.cache-invalidation on
# After 'timeout' seconds since the time client accessed any file, cache-invalidation notifications are no longer sent to that client.
# Default value: 60 seconds.
m gluster vol set shared features.cache-invalidation-timeout 300

# Disable gluster built-in NFS in favor of nfs-ganesha
a gluster vol set shared nfs.disable on

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
m showmount -e

# Mount shared volume via gluster on host for testing
mkdir -p "$HOME/tmp/gluster"
sudo mount -t glusterfs "$IP_OF_MASTER:/shared" "$HOME/tmp/gluster"

# Mount shared volume via nfs on host for testing
mkdir -p "$HOME/tmp/nfs"
sudo mount -t nfs -o vers=4.1,proto=tcp "$IP_OF_MASTER:/shared" "$HOME/tmp/nfs"
