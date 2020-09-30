
# Kustomize

### Combining yaml files

Simple example of using Kustomize via ```kubectl kustomize``` to concatenate yaml files into a single file

See:
- https://levelup.gitconnected.com/kubernetes-merge-multiple-yaml-into-one-e8844479a73a

You can concatenated the following files into one deploy_web.yaml file using the below command:
- deploy_web1.yaml
- deploy_web2.yaml
- deploy_web3.yaml

``` kubectl kustomize build conf-files > deploy_web.yaml ```

