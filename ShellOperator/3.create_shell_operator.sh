
NS=example-monitor-pods

kubectl get pods -n $NS | grep shell-operator && kubectl delete -n $NS -f shell-operator.yaml

kubectl apply -n $NS -f shell-operator.yaml

