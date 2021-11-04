#!/bin/bash

mkdir -p certs

# Generate CA key and certificate
openssl req -x509 -sha256 -newkey rsa:4096 -keyout certs/ca.key -out certs/ca.crt -days 356 -nodes -subj '/CN=The Great Test Cert Authority'

# Generate Server key and certificate, and sign with CA certificate

CREATE_SERVER_KEY_CERT() {
    host=$1; shift
    HOST=$1; shift

    openssl req -new -newkey rsa:4096 -keyout certs/$host.key -out certs/$host.csr -nodes -subj "/CN=$HOST"
    openssl x509 -req -sha256 -days 365 -in certs/$host.csr -CA certs/ca.crt -CAkey certs/ca.key -set_serial 01 -out certs/$host.crt

    kubectl create secret generic certs-$host --from-file=tls.crt=certs/$host.crt --from-file=tls.key=certs/$host.key --from-file=ca.crt=certs/ca.crt
}

CREATE_SERVER_KEY_CERT ingress1 ingress1-g15.mjbright.click
CREATE_SERVER_KEY_CERT vote vote-g15.mjbright.click
CREATE_SERVER_KEY_CERT quiz quiz-g15.mjbright.click

