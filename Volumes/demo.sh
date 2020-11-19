#!/bin/bash

DIR=$(dirname $0)

TMPDIR=~/tmp/demos
mkdir -p $TMPDIR

#cd $DIR

die() { echo "$0: die - $*" >&2; exit 1; }

DEMOS_RC=../../demos.rc

[ ! -f $DEMOS_RC ] && die "[$PWD] no such file as '$DEMOS_RC'"
. $DEMOS_RC


#press() {
#    echo "$*"
#    echo "Press <return>"
#    read DUMMY
#    [ "$DUMMY" = "q" ] && exit 0
#    [ "$DUMMY" = "Q" ] && exit 0
#}
#
#RUN() {
#    echo; press "-- $*"
#    $*
#}

echo
HL1 "In another window: run command" 
PRESS "watch kubectl get pv,pvc,pods"

RUN_EMPTYDIR_DEMO() {
    #cd emptyDir
    die "TODO"

    TMP_YAML=$TMPDIR/tmp_pod.yaml
    POD_YAML=$TMPDIR/pod.yaml
    POD2_YAML=$TMPDIR/pod2.yaml
    POD2_ED_YAML=$TMPDIR/pod2_emptyDir.yaml

    HL1 "First we will create an initial pod.yaml using '--dry-run'"
    CMD="kubectl run pv-demo --image mjbright/ckad-demo:alpine1 --dry-run=client -o yaml"
    RUN $CMD

    $CMD > $TMP_YAML
    grep -ivE "creationTimestamp|dnsPolicy|restartPolicy" $TMP_YAML | grep -v '{}' > $POD_YAML
    PRESS

    echo; echo "We first remove some 'empty' fields:"
    diff $TMP_YAML $POD_YAML
    PRESS

    echo; echo "We then append a 2nd container spec into the PodSpec:"
    PRESS
    cp $POD_YAML $POD2_YAML
    cat >> $POD2_YAML <<EOF
  - image: mjbright/ckad-demo:alpine1
    name: pv-demo2
    # Sleep 1hr:
    # We need some non-default command else will fail to listen on port 80
    command: ['/bin/sleep', '3600']
EOF

    diff $POD_YAML $POD2_YAML


    echo; echo "We then"
    echo "- add a volume definition"
    echo "- mount the volume in the second container"
    echo "- moify the 2nd container's 'command'"

    cat > $POD2_ED_YAML <<"EOF"
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: pv-demo-2-ed
  name: pv-demo-2-ed
spec:
  volumes:
  - name: ed
    emptyDir: {}

  containers:

  - image: mjbright/ckad-demo:alpine1
    name: pv-demo
    volumeMounts:
    - mountPath: /m1
      name: ed

  - image: mjbright/ckad-demo:alpine1
    name: pv-demo2
    command: ['/bin/sh', '-c', 'while true; do echo $(hostname): $(date) >> /m2/date.log; sleep 1; done']
    volumeMounts:
    - mountPath: /m2
      name: ed

  dnsPolicy: ClusterFirst
  restartPolicy: Always
EOF

    cat $POD2_ED_YAML

    die "TODO"
    #cd $DIR
}

RUN_HOSTPATH_DEMO() {
    die "TODO"
    #cd hostPath
    #cd $DIR
}

RUN_HOSTPATH_PC_PVC_DEMO() {
    #cd hostPath_PV_PVC

    RUN kubectl delete -f ./

    SECTION1 "Creating Persistent Volumes for initial demo"
    FILES="./pv_hostpath.yaml ./pv2_hostpath.yaml ./pv3_hostpath.yaml ./pvc.yaml ./pod_hostpath_pvc.yaml"
    for FILE in $FILES; do
        RUN cat $FILE
        RUN kubectl create -f $FILE
    done

    echo; kubectl get pods -o wide
    NODE=$( kubectl get pods -o custom-columns=NODE:.spec.nodeName --no-headers )

    [ -z "$NODE" ] && NODE="worker2"
    read -p "Enter node name [$NODE]: " NODE_CHOICE
    [ ! -z "$NODE_CHOICE" ] && NODE="$NODE_CHOICE"

    #VOL=/tmp/data01
    VOL=/tmp/data03
    RUN ssh $NODE ls -al ${VOL}/
    RUN ssh $NODE tail -100f ${VOL}/date.log

    SECTION1 "Creating extra Persistent Volumes with StorageClass"
    FILES="./pv4_sc_hostpath.yaml ./pv5_sc_hostpath.yaml ./pvc2_sc.yaml ./pod2_hostpath_pvc2.yaml"
    for FILE in $FILES; do
        RUN cat $FILE
        RUN kubectl create -f $FILE
    done

    RUN kubectl delete -f ./

    cd $DIR
}

case $PWD in
    *emptyDir) RUN_EMPTYDIR_DEMO;;
    *hostPath) RUN_HOSTPATH_DEMO;;
    *hostPath_PV_PVC) RUN_HOSTPATH_PC_PVC_DEMO;;

    *) die "[$PWD] Change to specific dir ( emptyDir, hostPath or hostPath_PV_PVC)";;
esac


exit $?

## -----------------------------------------------------------------------------------------------------

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


