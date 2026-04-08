#!/bin/bash

EC_DIR="$HOME/event_camera"
DATA_DIR="${1:-$EC_DIR/calibration_data}"

xhost +local:root

docker run -it --rm \
    --privileged \
    --net=host \
    --ipc=host \
    -e "DISPLAY=$DISPLAY" \
    -e "QT_X11_NO_MITSHM=1" \
    -v "/tmp/.X11-unix:/tmp/.X11-unix:rw" \
    -v "/dev/bus/usb:/dev/bus/usb" \
    -v "/run/udev:/run/udev:ro" \
    -v "/run/ueyed:/run/ueyed" \
    -v "$EC_DIR:/workspace" \
    -v "$DATA_DIR:/data" \
    camera_driver

xhost -local:root
