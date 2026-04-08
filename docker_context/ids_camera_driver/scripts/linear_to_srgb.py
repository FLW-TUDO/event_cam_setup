#!/usr/bin/env python3

import rospy
from sensor_msgs.msg import Image
from cv_bridge import CvBridge
import tensorflow as tf
import tensorflow_graphics as tfg
import numpy as np

class LinearToSRGBNode:
    def __init__(self):
        rospy.init_node('linear_to_srgb_converter', anonymous=True)

        # Parameters
        self.input_topic = rospy.get_param("~input_topic", "/rgb/image_resized")
        self.output_topic = rospy.get_param("~output_topic", "/rgb/image_srgb")

        # ROS Tools
        self.bridge = CvBridge()
        self.pub = rospy.Publisher(self.output_topic, Image, queue_size=10)

        # Subscribe to the input topic
        rospy.Subscriber(self.input_topic, Image, self.image_callback)

    @staticmethod
    def linear_to_srgb(image):
        return tf.where(
            image <= 0.0031308,
            image * 12.92,
            1.055 * tf.pow(image, 1.0 / 2.4) - 0.055,
        )

    def image_callback(self, msg):
        try:
            linear_rgb_image = self.bridge.imgmsg_to_cv2(msg, desired_encoding="passthrough")
            linear_rgb_image = linear_rgb_image / 255.0  # Normalize to [0, 1]

            linear_rgb_tensor = tf.convert_to_tensor(linear_rgb_image, dtype=tf.float32)
            srgb_tensor = self.linear_to_srgb(linear_rgb_tensor)
            srgb_image = srgb_tensor.numpy()
            srgb_image = np.clip(srgb_image * 255.0, 0, 255).astype(np.uint8)

            srgb_msg = self.bridge.cv2_to_imgmsg(srgb_image, encoding="bgr8")
            self.pub.publish(srgb_msg)

        except Exception as e:
            rospy.logerr(f"Error in converting Linear RGB to sRGB: {e}")

    def run(self):
        rospy.spin()

if __name__ == "__main__":
    try:
        node = LinearToSRGBNode()
        node.run()
    except rospy.ROSInterruptException:
        pass
