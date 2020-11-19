
# Volumes demo

## 1. emptyDir

This simple demo shows the creation of a Pod yaml manifest for 2 containers sharing an emptyDir volume

To run the emptyDir demo
- cd emptyDir
- follow the instructions in the README.md there

One container in the Pod writes the hostname and date every second to a file.

The file - date.log in the volume - is visible from both containers in the Pod.

The date.log file is destroyed when the Pod is destroyed

## 2. hostPath

This simple demo shows the creation of a Pod yaml manifest for 2 containers sharing an hostPath volume

To run the hostPath demo
- cd hostPath
- follow the instructions in the README.md there

One container in the Pod writes the hostname and date every second to a file.

The file - date.log in the volume - is created on **the host where the Pod runs**.

So note that on that node /tmp/hpstpath is created with date.log in it.

The other node does not have this path.

The date.log file remains after the Pod is destroyed

## 3. hostPath_PV_PVC

To run the hostPath_PV_PVC demo
- cd hostPath_PV_PVC
- Run the ../demo/.sh script

### Demo1:

In this demo we create a set of PVs (Persistent Volumes) with different sizes and access modes.

We then create a PVC (Persistent Volume Claim) and we see that it is successfully bound to one of the PVs.

Note that the PVC is assigned the smallest available PV which has the requested access mode.

We then create a Pod which is able to mount the volume (PVC).

Note that in this example the PV/PVC abstract the volume type - only the PV "knows" that the volume is of type hostPath.

The PodSpec specifies a Volume of type PersistentVolumeClaim.

### Demo2:

In this second demo we create 2 new PVs for which we have specified a StorageClass of either 'large-slow' or 'small-fast'

We then create a claim with storageClass 'large-slow' and we observe that of the 5 PVs now available we are assigned the one with StorageClass 'large-slow'.

