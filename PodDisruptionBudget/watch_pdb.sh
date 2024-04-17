
NODES="cp worker"

while true; do
    echo "--------------------------------------"
    for NODE in $NODES; do
        NUM=$( kubectl get pods -l app=test-deploy -o wide 2>&1 | grep -c " $NODE " )
        echo "Number of test-deploy Pods on Node $NODE: $NUM"
    done
    sleep 1
done

