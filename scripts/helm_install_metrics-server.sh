#!/bin/bash

RUN() {
    CMD=$*
    echo; echo "-- $CMD"
    eval $CMD
    RET=$?
    [ $RET -ne 0 ] && echo "... returned $RET"
}

RUN helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/

RUN helm search repo metrics-server

RUN kubectl create ns metrics-server

echo helm upgrade --install -n metrics-server metrics metrics-server/metrics-server --version 3.8.2 --set args='{--kubelet-preferred-address-types=InternalIP,--kubelet-insecure-tls}'
helm upgrade --install -n metrics-server metrics metrics-server/metrics-server --version 3.8.2 --set args='{--kubelet-preferred-address-types=InternalIP,--kubelet-insecure-tls}'

echo "Waiting for metrics to appear:"
RUN kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes"
while ! kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" 2>/dev/null; do echo -n .; sleep 3; done

RUN kubectl top nodes --sort-by cpu

RUN kubectl top pods  --sort-by cpu -A


