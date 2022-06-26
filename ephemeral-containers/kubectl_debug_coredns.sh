
# Obtain the name of one of the core dns Pods:

echo; echo "Obtaining name of one of the coredns Pods:"
POD1=$(  kubectl -n kube-system get po |& grep -m1 coredns | awk ' { print $1; }' )
echo "... $POD1"

#kubectl -n kube-system debug coredns-6d4b75cb6d-2llg9 --image mjbright/k8s-demo:alpine1
#kubectl -n kube-system exec -it coredns-6d4b75cb6d-2llg9 -c debugger-68gwk -- sh

# Attach an alpine image to that Pod:

echo; echo "Attaching to pod $POD1"
set -x
kubectl -n kube-system debug $POD1 --image mjbright/k8s-demo:alpine1
set +x

echo; echo "Obtaining the name of the ephemeral Container:"

set -x
DEBUG_C=$( kubectl -n kube-system get po $POD1 -o json | jq -r  '.spec.ephemeralContainers[0].name' )
set -x

echo; echo "Starting a shell in the debug containwr ... of Pod $POD1:"
echo "Note: ps will show processes of both the debug and '$DEBUG_C' Container"
echo "Note: look in /proc/1/root to access the Container filesystem ... careful !!"
set -x
kubectl -n kube-system exec -it $POD1 -c $DEBUG_C -- sh
set +x



