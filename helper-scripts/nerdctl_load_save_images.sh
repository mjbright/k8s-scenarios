#!/usr/bin/env bash

## Usage: ---------------------------------------------------------------------

# TO SAVE all images (filtered by $FILTER / $REMOVE_FILTER below):
#
#    nerdctl_load_save_images.sh -s ~/tmp/images.tbz2
#
# or simply:
#    nerdctl_load_save_images.sh
#
# TO LOAD all images (filtered by $FILTER / $REMOVE_FILTER below):
#
#    nerdctl_load_save_images.sh -l ~/tmp/images.tbz2

## Func: ----------------------------------------------------------------------

die() { echo "$0: die - $*" >&2; exit -1; }

## Args: ----------------------------------------------------------------------

LOAD_IMAGES=0
INPUT_TAR=""

# Docker hub only (default):
FILTER="^docker.io"

# Exclude sha256 images (default):
REMOVE_FILTER="^sha256|registry.k8s.io|quay.io|@sha256"

[ $# -eq 0 ] && set -- --save /tmp/images.tgz

while [ $# -ne 0 ]; do
    case $1 in
        -l|--load) LOAD_IMAGES=1; shift; INPUT_TAR=$1;;
        -s|--save) LOAD_IMAGES=0; shift; OUTPUT_TAR=$1;;

        -f|--filter) shift; FILTER=$1;;
        -rf|--remove-filter) shift; REMOVE_FILTER=$1;;

        *) die "Unknown option: '$1'";;
    esac
    shift
done

## Main: ----------------------------------------------------------------------

if [ $LOAD_IMAGES -ne 0 ]; then
    # die "Not implemented"
    # sudo nerdctl -n k8s.io image load -i ~/tmp/tmp.images/docker.io-mjbright-k8s-demo_1

    IMAGE_DIR=~/tmp/tmp.images.new
    mkdir -p $IMAGE_DIR

    cd       ${IMAGE_DIR}/
    tar xf   $INPUT_TAR
    mv */* .
    rmdir */

    ls -alh

    for IMAGE_FILE in *; do
        CMD="sudo nerdctl -n k8s.io image load -i $IMAGE_FILE"
        echo; echo "-- $CMD"; $CMD
    done
else
    IMAGE_DIR=~/tmp/tmp.images
    rm   -rf ${IMAGE_DIR}
    mkdir -p ${IMAGE_DIR}

    IMAGES=$( 
      sudo nerdctl -n k8s.io image ls --format '{{json .Name}}' | sed -e 's/"//g' | grep -E "$FIlTER" | grep -E -v "$REMOVE_FILTER"
    )
    for IMAGE in $IMAGES; do
        IMAGE_TAR=${IMAGE_DIR}/$( echo $IMAGE | sed -e 's?/?-?g' -e 's/:/_/g' )

        CMD="sudo nerdctl -n k8s.io image save $IMAGE -o $IMAGE_TAR"
        echo; echo "-- $CMD"; $CMD
        ls -alh $IMAGE_TAR
    done

    echo
    du -sh   ${IMAGE_DIR}
    cd       ${IMAGE_DIR}/..

    CMD="tar jcvf images.tbz2 tmp.images"
    echo; echo "-- $CMD"; $CMD
    ls -alh images.tbz2
fi

exit



  188  2024-04-13 08:53:09 sudo nerdctl image list -n k8s.io
  189  2024-04-13 08:53:27 sudo nerdctl -n k8s.io image ls
  190  2024-04-13 08:53:35 sudo nerdctl -n k8s.io image ls -v
  191  2024-04-13 08:53:40 sudo nerdctl -n k8s.io image ls --help
  192  2024-04-13 08:54:00 sudo nerdctl -n k8s.io image ls --digests
  193  2024-04-13 08:54:31 sudo nerdctl -n k8s.io image inspect registry.k8s.io/pause
  194  2024-04-13 08:54:37 sudo nerdctl -n k8s.io image inspect registry.k8s.io/pause:3.6
  195  2024-04-13 08:55:02 sudo nerdctl -n k8s.io image inspect registry.k8s.io/pause:3.6 --format '.Id'
  196  2024-04-13 08:55:09 sudo nerdctl -n k8s.io image inspect registry.k8s.io/pause:3.6 --format '{.json .Id}'
  197  2024-04-13 08:55:14 man nerdctl
  198  2024-04-13 08:55:24 sudo nerdctl -n k8s.io image inspect registry.k8s.io/pause:3.6 --help
  199  2024-04-13 08:55:42 sudo nerdctl -n k8s.io image inspect registry.k8s.io/pause:3.6 --format '{{json .Id}}'
  200  2024-04-13 08:55:52 sudo nerdctl -n k8s.io image inspect registry.k8s.io/pause:3.6 --format '{{json .Id}}'
  201  2024-04-13 08:56:04 sudo nerdctl -n k8s.io image ls --format '{{json .Id}}'
  202  2024-04-13 08:56:32 sudo nerdctl -n k8s.io image ls --format '{{json .}}'
  204  2024-04-13 08:56:57 sudo nerdct export
  205  2024-04-13 08:57:07 sudo nerdctl -n k8s.io image export
  206  2024-04-13 08:57:11 sudo nerdctl -n k8s.io image
  207  2024-04-13 08:57:33 sudo nerdctl -n k8s.io image save "sha256:ee1b5fd4c83a6d7dd4db7a77ebcbca0c1bb99b7ca68b042f7b3052b4f4846441" x.tgx
  208  2024-04-13 08:57:41 sudo nerdctl -n k8s.io image save "sha256:ee1b5fd4c83a6d7dd4db7a77ebcbca0c1bb99b7ca68b042f7b3052b4f4846441" -o x.tgz
  209  2024-04-13 08:57:43 ll x.tgz 
  210  2024-04-13 08:57:48 tar tf x.tgz 
  211  2024-04-13 08:57:53 history
  212  2024-04-13 08:58:11 vi nerdctl_load_save_images.sh
  213  2024-04-13 08:58:17 chmod +x nerdctl_load_save_images.sh
  214  2024-04-13 08:58:26 history 30 >> nerdctl_load_save_images.sh
  215  2024-04-13 08:58:27 vi nerdctl
  216  2024-04-13 08:58:38 history 30 
  217  2024-04-13 08:58:44 history 30 > nerdctl_load_save_images.sh
