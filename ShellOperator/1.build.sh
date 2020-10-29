
IMAGE=registry.mycompany.com/shell-operator:monitor-pods
IMAGE=mjbright/shell-operator:monitor-pods

sudo docker build -t "$IMAGE" .
sudo docker login
sudo docker push $IMAGE

