#!/bin/bash

# -- Args: --------------------------------------------

POD_SPEC="-l app=debug-ectest"

[ ! -z "$1" ] && POD_SPEC="$*"

[ "$POD_SPEC" = "etcd" ] && POD_SPEC="-n kube-system etcd-master";

# -- Main: --------------------------------------------

echo "kubectl get pod $POD_SPEC -o json"
if [ "${POD_SPEC#-l}" != "$POD_SPEC" ]; then
    kubectl get pod $POD_SPEC -o json | jq -C -c '.items[].spec.ephemeralContainers[] | { name, command }' | sed 's/^/  /'
else
    kubectl get pod $POD_SPEC -o json | jq -C -c '.spec.ephemeralContainers[] | { name, command }'         | sed 's/^/  /'
fi

