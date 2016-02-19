FROM vlisivka/centos7-systemd-unpriv
MAINTAINER Volodymyr M. Lisivka <vlisivka@gmail.com>

# For proper work of console tools
ENV TERM xterm

# Install repositories
RUN yum install -y epel-release.noarch centos-release-gluster37.noarch

# Install packages
RUN yum -y swap -- install \
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
# Dependency problem with dbus, will be installed by next yum install command.
#  glusterfs-ganesha \

# Tool to set/check extended attributes on files
  attr \

# dbus-send is required by glusterfs-ganesha
  dbus \

# Tools for developers
  mc htop net-tools bash-completion \

# Glusterfs requires nfsutils,
# nfsutils requires kmod, which in turn required drac,
# which requires systemd >219, while systemd-container is 208,
# so remove systemd-container to avoid conflicts.
# FIXME: recompile glusterfs without kernel nfs server.
  -- remove \
  systemd-container \
  systemd-container-libs

RUN yum install -y glusterfs-ganesha \
  && yum -y clean all

# Mask (create override which points to /dev/null) system services, which
# cannot be started in container anyway.
#RUN systemctl mask \
#    proc-fs-nfsd.mount \
#    var-lib-nfs-rpc_pipefs.mount

# Remove broken link
RUN rm -f /usr/lib/systemd/system/dbus-org.freedesktop.network1.service

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
