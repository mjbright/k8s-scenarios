
# Create yaml manifest

1. Create initial pod.yaml
2. Create pod_hostpath.yaml
  - Add command to loop and write hostname/date to volume

# Create the Pod

1. Observe where the Pod is running - which node?
```sh
$ kubectl get pods -o wide
NAME           READY   STATUS    RESTARTS   AGE   IP                NODE      NOMINATED NODE   READINESS GATES
pv-hostpasth   2/2     Running   0          5s    192.168.189.113   worker2   <none>           <none>
```
2. Log to the node and search under /tmp/hostpath for date.log

# Now kill the Pod

Note that tailing of container log file now stalls ... but the data is preserved.

Note that data is only on that host



