

# Assumes NFS is already configured on all nodes using NFS volume at /opt/sfw

echo; echo "-- Using NFS provisioner:"

kubectl get storageclasses,pv,pvc
sudo find /opt/sfw/

echo; echo "-- Creating test-pod (will remain Pending for now)"
kubectl create -f test-pod.yaml 
kubectl get pods

read
kubectl describe pods test-pod 

echo; echo "-- Creating PVC which will create and be bound to a PV"
kubectl get pv,pvc
kubectl create -f test-claim.yaml 

sleep 2
echo "Pod should now be running:"
kubectl get pods,pv,pvc

sudo find /opt/sfw/

