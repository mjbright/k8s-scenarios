#!/bin/bash

helm version
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

helm install my-release ingress-nginx/ingress-nginx

POD_NAME=$(kubectl get pods -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD_NAME -- /nginx-ingress-controller --version


