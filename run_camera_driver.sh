#!/bin/bash
# Run the camera_driver container for live recording on Jetson.
# Usage: ./run_camera_driver.sh [bags_dir]
#
# Inside the container:
#   roslaunch RGB_event_cam_stereo.launch          # stream all cameras
#   roslaunch record_wp1.launch exposure_us:=5000  # cameras only, no record
#   /RGB_Event_cam_system/record_wp1_docker.sh 5 30 my_label  # full recording

RGB_DIR="$HOME/event/RGB_Event_cam_system"
BAGS_DIR="${1:-$HOME/bags}"
VICON_IP="192.168.2.221"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

mkdir -p "$BAGS_DIR"

[ -n "$DISPLAY" ] && xhost +local:root

docker run -it --rm \
    --privileged \
    --net=host \
    --ipc=host \
    -e "DISPLAY=${DISPLAY:-}" \
    -e "QT_X11_NO_MITSHM=1" \
    -e "ROS_PACKAGE_PATH=/RGB_Event_cam_system:/catkin_ws/src:/opt/ros/noetic/share" \
    -e "VICON_IP=${VICON_IP}" \
    -e "HOST_UID=${HOST_UID}" \
    -e "HOST_GID=${HOST_GID}" \
    -v "/tmp/.X11-unix:/tmp/.X11-unix:rw" \
    -v "/dev/bus/usb:/dev/bus/usb" \
    -v "/run/udev:/run/udev:ro" \
    -v "${RGB_DIR}:/RGB_Event_cam_system" \
    -v "${BAGS_DIR}:/bags" \
    camera_driver

[ -n "$DISPLAY" ] && xhost -local:root
