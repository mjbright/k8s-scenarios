#!/bin/bash

POD_SPEC="-n kube-system etcd-master"
[ ! -z "$1" ] && POD_SPEC="$*"

kubectl get pod $POD_SPEC -o json | jq -c '.spec.ephemeralContainers[] | { name, command }'

