#!/bin/bash

cd $(dirname $0)

set -x
time kind create cluster --config kind-cluster-1M-5W.ipvs.yaml
