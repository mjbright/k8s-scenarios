#!/bin/bash

RUN() {
    CMD=$*
    echo; echo "---- $CMD"
    echo "Press <enter>"
    local DUMMY
    read DUMMY
    [ "$DUMMY" = "q" ] && exit
    [ "$DUMMY" = "Q" ] && exit

    [ "$DUMMY" = "s" ] && return
    [ "$DUMMY" = "S" ] && return

    eval $CMD
}

echo
echo "-- YAML representation of a 'generic' secret from literal key=value pairs:"
RUN kubectl create secret generic mysecret --from-literal='password=mys3cr3tp0ss' --from-literal='username=mike' --dry-run=client -o yaml

echo
echo "-- But see how we can 'decode' those 'secret' values as they are not encrypted"
echo
echo "-- Decoding the password:"
RUN "kubectl create secret generic mysecret --from-literal='password=mys3cr3tp0ss' --from-literal='username=mike' --dry-run=client -o yaml | awk '/password:/ { print \$2; }' | base64 -d; echo"
echo
echo "-- Decoding the username:"
RUN "kubectl create secret generic mysecret --from-literal='password=mys3cr3tp0ss' --from-literal='username=mike' --dry-run=client -o yaml | awk '/username:/ { print \$2; }' | base64 -d; echo"
