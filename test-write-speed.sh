#!/bin/bash
set -ue

main() {
  local TARGET_DIR="${1:?ERROR: Argument is required: target directory to write to.}"
  local SIZE="${2:?ERROR: Argument is required: size of file, e.g. 1M.}"
  local NUMBER="${3:?ERROR: Argument is required: number of files to write, e.g. 3.}"
  shift 3 # Rest of arguments are options for dd, like oflag=sync,dsync,direct , etc.

  for((I=1; I<=NUMBER; I++))
  do
    dd if=/dev/zero bs="$SIZE" count=1 of="$TARGET_DIR/file-$SIZE-$I.bin" "$@" || {
      echo "ERROR: Cannot write to \"$TARGET_DIR/file-$SIZE-$I.bin\"." >&2
      return 1
    }
  done
}

main "$@"
