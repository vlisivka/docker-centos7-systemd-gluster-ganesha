#!/bin/bash
set -ue
# See --help for details.
# Author: Volodymyr M. Lisivka <vlisivka@gmail.com>

BIN_DIR="$(dirname "$0")"

BRICK_NAME="${BRICK_NAME:-centos7_gluster_brick}"
DOCKER_IMAGE="${DOCKER_IMAGE:-vlisivka/centos7-systemd-gluster-ganesha}"

RUN_OPTIONS=( )

# Run a function multiple times, like xargs.
mul() {
  local FUNCTION="${1:?ERROR: Argument is required: function to call.}"
  local NUMBER_OF_BRICKS="${2:?ERROR: Argument is required: number of calls.}"
  shift 2 # Rest of argumens are arguments to function, which will be called

  local EXIT_CODE=0

  local I
  for((I=1; I<=NUMBER_OF_BRICKS; I++))
  do
    echo "INFO: $FUNCTION $I $@"
    $FUNCTION "$I" "$@" || EXIT_CODE=$?
  done

  return $EXIT_CODE
}

# Run single brick.
run_brick() {
  local BRICK_NUMBER="${1:?ERROR: Argument is required: brick number.}"

  local NAME="$BRICK_NAME$BRICK_NUMBER"

  docker run "${RUN_OPTIONS[@]:+${RUN_OPTIONS[@]}}" -d --cap-add=SYS_ADMIN --ulimit nofile=1048576:1048576 --stop-signal=$(kill -l RTMIN+3) -v /sys/fs/cgroup:/sys/fs/cgroup:ro --name "$NAME" "$DOCKER_IMAGE"
}

stop_brick() {
  local BRICK_NUMBER="${1:?ERROR: Argument is required: brick number.}"

  local NAME="$BRICK_NAME$BRICK_NUMBER"

  docker stop "$NAME" || :
  docker rm "$NAME" || :
}

exec_brick() {
  local BRICK_NUMBER="${1:?ERROR: Argument is required: brick number.}"
  shift 1 # Rest are arguments to exec

  local NAME="$BRICK_NAME$BRICK_NUMBER"

  docker exec "$NAME" "$@"
}

exec_it_brick() {
  local BRICK_NUMBER="${1:?ERROR: Argument is required: brick number.}"
  shift 1 # Rest are arguments to exec

  local NAME="$BRICK_NAME$BRICK_NUMBER"

  docker exec -it "$NAME" "$@"
}

# Return only first IP of the host
ip_of_brick() {
  local BRICK_NUMBER="${1:?ERROR: Argument is required: brick number.}"
  exec_brick "$BRICK_NUMBER" hostname -I | cut -d ' ' -f 1
}

logs_of_brick() {
  local BRICK_NUMBER="${1:?ERROR: Argument is required: brick number.}"

  local NAME="$BRICK_NAME$BRICK_NUMBER"

  docker logs "$NAME"
}

main() {
  local COMMAND="${1:?ERROR: Argument is required: command to run. Use --help to list available commands.}"
  shift 1

  case "$COMMAND" in
    run)
      mul run_brick "$@" || return $?
    ;;
    stop)
      mul stop_brick "$@" || return $?
    ;;
    exec)
      mul exec_brick "$@" || return $?
    ;;
    exec_one)
      exec_brick "$@" || return $?
    ;;
    exec_it)
      mul exec_it_brick "$@" || return $?
    ;;
    exec_it_one)
      exec_it_brick "$@" || return $?
    ;;
    ip_of)
      mul ip_of_brick "$@" || return $?
    ;;
    ip_of_one)
      ip_of_brick "$@" || return $?
    ;;
    logs_of)
      mul logs_of_brick "$@" || return $?
    ;;
    logs_of_one)
      logs_of_brick "$@" || return $?
    ;;
    help|--help|-h)
      echo "
NAME
    cluster.sh - execute a command on list of virtual glusterfs bricks in docker containers

SYNOPSIS

    cluster.sh COMMAND NUM [ARGUMENTS...]

DESCRIPTION

    COMMAND  - run stop exec exec_one exec_it exec_it_one ip_of ip_of_one logs_of logs_of_one help

    NUM - number of bricks or number of a brick.

    ARGUMENTS - command arguments (if any).

COMMANDS

    run - run containers.

    stop - stop containers.

    exec COMMAND [ARGUMENTS...] - execute a command with arguments on containers.

    exec_one COMMAND [ARGUMENTS...] - execute a command with arguments on a single container.

    exec_it COMMAND [ARGUMENTS...]  - same ae exec, but with -it (interactive terminal) option.

    exec_it_one COMMAND [ARGUMENTS...]  - same ae exec_one, but with -it (interactive terminal) option.

    ip_of - print internal IP of each node.

    ip_of_one - print internal IP of a node.

    logs_of - print docker logs of each node.

    logs_of_one - print docker logs of a node.

    help - print this help.

ENVIRONMENT VARIABLES

    BRICK_NAME - name for docker containers. Brick number will be appended to name. Default value: \"centos7_gluster_brick\".

    DOCKER_IMAGE - name of image to run. Default value: \"vlisivka/centos7-systemd-gluster-ganesha\".

EXAMPLES

    # Run 3 bricks
    cluster.sh run 3

    # Execute command hostname on each brick
    cluster.sh exec 3 hostname

    # Get IP of first brick
    cluster.sh exec_one 1 ip_of

    # Run interactive shell on second brick
    cluster.sh exec_it_one 2 bash

    # Stop 3 bricks
    cluster.sh stop 3

"
      return 0
    ;;
    *)
      echo "ERROR: Unknown command. Use \"--help\" to list available commands." >&2
      return 1
    ;;
  esac
}

main "$@"
