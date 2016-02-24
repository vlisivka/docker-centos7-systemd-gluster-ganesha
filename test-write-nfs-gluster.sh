#!/bin/bash
set -ue
BIN_DIR="$(dirname "$0")"

DD_OPTIONS=( '' 'oflag=sync,dsync' 'oflag=direct' )

MOUNTPOINTS=( "$HOME/tmp/gluster" "$HOME/tmp/nfs" )

FILE_SIZES=( 1M 50K 1K )

for OPTIONS in "${DD_OPTIONS[@]}"
do
  for SIZE in "${FILE_SIZES[@]}"
  do
    for MOUNTPOINT in "${MOUNTPOINTS[@]}"
    do
      echo "INFO: Testing $MOUNTPOINT with dd $OPTIONS using 3 $SIZE files."
      time sudo "$BIN_DIR"/test-write-speed.sh "$MOUNTPOINT" $SIZE 3  $OPTIONS || exit 1
    done
  done
done
