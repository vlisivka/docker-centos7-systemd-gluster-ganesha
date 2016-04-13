FROM docker.io/centos:7
MAINTAINER Volodymyr M. Lisivka <vlisivka@gmail.com>

# For proper work of console tools
ENV TERM xterm

# For proper work of systemd in container
ENV container docker

# NOTE: Systemd needs /sys/fs/cgroup directoriy to be mounted from host in
# read-only mode.

# Systemd needs /run directory to be a mountpoint, otherwise it will try
# to mount tmpfs here (and will fail).
VOLUME /run

# Run systemd by default, to start required services.
CMD ["/usr/sbin/init"]

# NOTE: Run container with "--stop-signal=$(kill -l RTMIN+3)" option to
# shutdown container using "docker stop CONTAINER", OR run
# /usr/local/sbin/shutdown.sh script as root from container and then kill
# container using "docker kill CONTAINER".

# Install repositories
RUN yum install -y epel-release.noarch centos-release-gluster37.noarch && \

# Install packages
  yum -y install \
# GlusterFS packages
  glusterfs \
  glusterfs-server \
  glusterfs-fuse \
  glusterfs-geo-replication \
  glusterfs-cli \
  glusterfs-api \

# NFS server "ganesha", with built-in support for gluster.
  nfs-ganesha \
  nfs-ganesha-gluster \
  glusterfs-ganesha \

# Tool to set/check extended attributes on files
  attr \
  which \

# dbus-send is required by glusterfs-ganesha
  dbus \

# Tools for developers
  mc htop net-tools bash-completion \

# Clean cache to save space in layer
  && yum -y clean all

# Enable services
RUN systemctl enable \
    rpcbind.service \
    glusterd.service \
    glusterfsd.service \
    nfs-ganesha.service \
    nfs-ganesha-lock.service

# NOTE: Portmapper can map any port for client, so use direct networking
# instead of exposing of some ports.
EXPOSE \
# Portmapper
  111 \
## NFS ganesha ports:
# ?
  564 \
# rquotad (portmapper)
  875 \
# NFS (portmapper)
  2049 \
# NLM (NFS Locking Manager)
  38824 \
# ?
  41154 \
## Glusterfs ports
#  Gluster Daemon
  24007 \
# Gluters management
  24008 \
#    (GlusterFS versions 3.4 and later) - Each brick for every volume on
# your host requires it’s own port. For every new brick, one new port will
# be used starting at 49152 for version 3.4 and above. If you have one
# volume with two bricks, you will need to open 49152 - 59153.
  49152-49162

COPY files/ /
