list(APPEND CMAKE_PREFIX_PATH "/opt/ros/noetic")

find_package(catkin REQUIRED COMPONENTS
  roscpp
  sensor_msgs
  cv_bridge
)

include_directories(
  ${catkin_INCLUDE_DIRS}
  /opt/ros/noetic/include
  /opt/ids/ueye/include
)