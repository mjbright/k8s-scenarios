
# nfs-provisioner

Based on 
- https://opensource.com/article/20/6/kubernetes-nfs-client-provisioning
  - NOTE: need different deployment for ARM/Raspberry Pi

- Issue in k8s 1.20+ (removal of selfLink):
  - https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/issues/25
  - changed image for nfs-provisioner to use gcr.io/k8s-staging-sig-storage/nfs-subdir-external-provisioner:v4.0.0

