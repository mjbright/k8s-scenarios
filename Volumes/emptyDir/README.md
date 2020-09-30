
# Create yaml manifest

1. Create initial pod.yaml
  - kubectl run pv-demo --image mjbright/ckad-demo:alpine1 --dry-run=client -o yaml > pod.yaml
  - remove null entries (creationTimeStamp)
  - remove empty {} entries

2. Create pod2.yaml
  - Duplicate container definition
  - rename container to container2
  - add a command on container2
    - e.g. command: ['/bin/sleep','3600'] to avoid port 80 conflict

3. Create pod2_emtptyDir.yaml
  - Add command to loop and write to emptyDir volume

# Create the Pod

1. Observe where the Pod is running - which node?
```sh
$ kubectl get pods -o wide
NAME           READY   STATUS    RESTARTS   AGE   IP                NODE      NOMINATED NODE   READINESS GATES
pv-demo-2-ed   2/2     Running   0          5s    192.168.189.113   worker2   <none>           <none>
```

2. Log to the node and search under /var/lib for date.log

e.g.

```sh
$ vagrant ssh worker2 -- sudo find /var/lib/kubelet/pods -name date.log
NUM_MASTERS=1 NUM_WORKERS=2
/var/lib/kubelet/pods/86a39c93-81a3-4d88-9e58-92205f515dc0/volumes/kubernetes.io~empty-dir/ed/date.log
```

```sh
$ vagrant ssh worker2 -- 'sudo find /var/lib/ -name date.log -exec ls -al {} \;'
NUM_MASTERS=1 NUM_WORKERS=2
-rw-r--r-- 1 root root 4698 Sep 30 05:09 /var/lib/kubelet/pods/86a39c93-81a3-4d88-9e58-92205f515dc0/volumes/kubernetes.io~empty-dir/ed/date.lo
```
```sh
$ vagrant ssh worker2 -- 'sudo find /var/lib/ -name date.log -exec tail -f {} \;'
NUM_MASTERS=1 NUM_WORKERS=2
Wed Sep 30 05:10:11 UTC 2020
Wed Sep 30 05:10:12 UTC 2020
Wed Sep 30 05:10:13 UTC 2020
Wed Sep 30 05:10:14 UTC 2020
Wed Sep 30 05:10:15 UTC 2020
Wed Sep 30 05:10:16 UTC 2020
Wed Sep 30 05:10:17 UTC 2020
Wed Sep 30 05:10:18 UTC 2020
Wed Sep 30 05:10:19 UTC 2020
Wed Sep 30 05:10:20 UTC 2020
Wed Sep 30 05:10:21 UTC 2020
Wed Sep 30 05:10:22 UTC 2020
```

Leave this running ...

# Connect to Pod

1. First connect to first container

Note only app listening on port 80

```sh
$ kubectl exec -it pv-demo-2-ed  -- sh
# ps
# df /m1
# ls -al /m1
# ls -al /m1

```
2. Then connect to second container

Note shell looping, writing to date.log

```sh
$ kubectl exec -it pv-demo-2-ed  -- sh
# ps
# df /m2
# ls -al /m2
# ls -al /m2

```
# Now kill the Pod

Note that tailing of container log file now stalls ... the data is lost.


