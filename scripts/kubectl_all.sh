#!/usr/bin/env bash

# USAGE: Script to perform kubectl commands on either
#
# - all contexts of the current kube config file, e.g.
#       kubectl_all.sh get pods
#
# - the current context for each of a comma-separated list of kubeconfig files, e.g.:
#       kubectl_all.sh -kc ~/.kube/config.cluster1~/.kube/config.cluster2,~/.kube/config.cluster3   get pods
#
# Derived from a suggestion here:
# - https://stackoverflow.com/questions/75986635/how-do-you-execute-multiple-kubectl-commands-for-multiple-clusters-in-parallel

die() { echo "$0: die - $*" >&2; exit 1; }

if [ "$1" = "-kc" ]; then
    shift
    KUBECONFIG_FILES=$( echo $1 | sed 's/,/ /g' )
    shift

    CONTEXTS=""

    for KUBECONFIG_FILE in $KUBECONFIG_FILES; do
        [ -f $KUBECONFIG_FILE ] || die "No such kubeconfig file as '$KUBECONFIG_FILE'"
        CONTEXTS+=" $( KUBECONFIG=$KUBECONFIG_FILE kubectl config current-context )"
    done

    echo "Operating on the following contexts from the provided kube config files:"
    echo "    $CONTEXTS"
else
    CONTEXTS=$( kubectl config get-contexts -o name )

    echo "Operating on the following contexts from your kube config file:"
    echo "    $CONTEXTS"
fi

#exit

SUB_COMMAND=$*

pids=()
for CONTEXT in $CONTEXTS; do
    (
set -x
    kubectl --context "${CONTEXT}" $SUB_COMMAND
    ) &
    pid=$!
    pids+=( $pid )
done
for pid in ${pids[@]}; do
    if wait ${pid}; then
        echo "DEBUG: pid=$pid: success"
    else
        exitcode=$?
        echo "WARNING: pid=${pid}: failure (exitcode=${exitcode})" >&2
    fi
done

