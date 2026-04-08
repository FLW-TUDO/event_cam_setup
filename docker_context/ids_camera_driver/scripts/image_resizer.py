#!/usr/bin/env python
import rospy
from sensor_msgs.msg import Image
from cv_bridge import CvBridge
import cv2

bridge = CvBridge()

def callback(image_msg):
    # Convert ROS Image to OpenCV
    cv_image = bridge.imgmsg_to_cv2(image_msg, desired_encoding="bgr8")
    # Resize Image
    resized = cv2.resize(cv_image, (640, 480))
    # Publish Resized Image
    pub.publish(bridge.cv2_to_imgmsg(resized, encoding="bgr8"))

rospy.init_node("image_resizer")
sub = rospy.Subscriber("/rgb/image_raw", Image, callback)
pub = rospy.Publisher("/rgb/image_resized", Image, queue_size=1)
rospy.spin()

