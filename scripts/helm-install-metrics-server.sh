#!/bin/bash

die() { echo "$0: die - $*" >&2; exit 1; }

which helm >/dev/null || die "You need to install helm first"

#NS="monitoring"
NS="metrics-server"

UNINSTALL() {
    helm uninstall -n $NS my-metrics-server
}

INSTALL() {
    kubectl create ns metrics-server
    # helm repo add metrics-server https://olemarkus.github.io/metrics-server
    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
    helm search repo metrics-server
    helm install my-metrics-server -n $NS metrics-server/metrics-server --set args='{--kubelet-preferred-address-types=InternalIP,--kubelet-insecure-tls}'
}

WAIT_ON_METRICS() {
    echo; echo "---- Waiting for metrics server to start"
    while ! kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" ; do sleep 5; done

    echo; echo "---- Waiting for first node metrics"
    while ! kubectl top nodes; do sleep 5; done

    echo; echo "---- Waiting for first pod metrics"
    while ! kubectl top pod -A; do sleep 5; done
}

kubectl get ns $NS || kubectl create ns $NS

if [ "$1" = "-d" ]; then
    UNINSTALL
    exit $?
fi

INSTALL
WAIT_ON_METRICS

set -x
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" | jq '.items[].metadata.name'
set +x
#kubectl get --raw "/apis/metrics.k8s.io/v1beta1/pods" | jq '.items[].metadata.name'
#kubectl get --raw "/apis/metrics.k8s.io/v1beta1/namespaces/default/pods" | jq '.items[].metadata.name'


