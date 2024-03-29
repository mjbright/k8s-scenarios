#!/bin/bash

# See: https://medium.com/@awkwardferny/configuring-certificate-based-mutual-authentication-with-kubernetes-ingress-nginx-20e7e38fdfca

which jq || sudo apt-get install -y jq

NODE_PORT=$( kubectl get svc my-release-ingress-nginx-controller -o json | jq '.spec.ports[0].nodePort' )

curl -L -H "Host: quiz-g15.mjbright.click" http://127.0.0.1:$NODE_PORT
curl -L -H "Host: quiz-g15.mjbright.click" --cert certs/quiz.crt --key certs/quiz.key https://127.0.0.1:$NODE_PORT
curl -L -H "Host: vote-g15.mjbright.click" --cert certs/vote.crt --key certs/vote.key https://127.0.0.1:$NODE_PORT
curl -L -H "Host: ingress1-g15.mjbright.click" --cert certs/ingress1.crt --key certs/ingress1.key https://127.0.0.1:$NODE_PORT


