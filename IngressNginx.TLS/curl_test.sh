
which jq || sudo apt-get install -y jq

NODE_PORT=$( kubectl get svc my-release-ingress-nginx-controller -o json | jq '.spec.ports[0].nodePort' )

curl -L -H "Host: quiz-g15.mjbright.click" 127.0.0.1:$NODE_PORT
curl -L -H "Host: vote-g15.mjbright.click" 127.0.0.1:$NODE_PORT
curl -L -H "Host: ingress1-g15.mjbright.click" 127.0.0.1:$NODE_PORT


