
NS=example-monitor-pods

kubectl create namespace $NS
kubectl create serviceaccount monitor-pods-acc -n $NS
kubectl create clusterrole monitor-pods --verb=get,watch,list --resource=pods
kubectl create clusterrolebinding monitor-pods --clusterrole=monitor-pods --serviceaccount=$NS:monitor-pods-acc
