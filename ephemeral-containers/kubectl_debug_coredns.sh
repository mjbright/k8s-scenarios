

POD1=$(  kubectl -n kube-system get po |& grep -m1 coredns | awk ' { print $1; }' )

#kubectl -n kube-system debug coredns-6d4b75cb6d-2llg9 --image mjbright/k8s-demo:alpine1
#kubectl -n kube-system exec -it coredns-6d4b75cb6d-2llg9 -c debugger-68gwk -- sh

set -x
kubectl -n kube-system debug $POD1 --image mjbright/k8s-demo:alpine1
set +x

DEBUG_C=$( kubectl -n kube-system get po coredns-6d4b75cb6d-2llg9 -o json | jq -r  '.spec.ephemeralContainers[0].name' )

set -x
kubectl -n kube-system exec -it $POD1 -c $DEBUG_C -- sh
set +x



