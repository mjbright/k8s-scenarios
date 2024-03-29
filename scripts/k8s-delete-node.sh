#!/usr/bin/env bash

die() { echo -e "$0:\n\tdie - $*" >&2; exit 1; }

[ -z "$1" ] && die "Usage: $0 <node>"

NODE=$1; shift

kubectl get no -o name | grep ^node/$NODE$ ||
    die "No such node as $NODE"

set -x
kubectl drain $NODE --ignore-daemonsets --delete-local-data
kubectl delete node $NODE
set +x

echo
echo "Node deletion complete:"
kubectl get no

echo
echo "Remember to run the following on the REMOVED NODE:"
echo "    sudo kuebadm reset"

exit

