

# Assumes NFS is already configured on all nodes using NFS volume at /opt/sfw

echo; echo "-- Setting up NFS provisioner:"
kubectl create -f rbac.yaml 
kubectl create -f deployment.yaml 
kubectl create -f class.yaml 

kubectl get storageclasses,pv,pvc


