#!/usr/bin/env python3
import sys
from ids_peak import ids_peak as peak
from ids_peak_ipl import ids_peak_ipl
#from pyueye import ueye
import calendar
import time
import rospy
from sensor_msgs.msg import Image
import cv2
import numpy as np

m_device = None
m_dataStream = None
m_node_map_remote_device = None

_ENCODING_CHANNELS = {"rgba8": 4, "rgb8": 3, "bgr8": 3, "bgra8": 4, "mono8": 1}

def numpy_to_imgmsg(arr, encoding):
    msg = Image()
    msg.height, msg.width = arr.shape[:2]
    msg.encoding = encoding
    msg.is_bigendian = 0
    msg.step = msg.width * _ENCODING_CHANNELS.get(encoding, arr.shape[2] if arr.ndim == 3 else 1)
    msg.data = arr.tobytes()
    return msg

def open_camera():
    global m_device, m_node_map_remote_device
    try:
        # Create instance of the device manager

        device_manager = peak.DeviceManager.Instance()

        # Update the device manager
        device_manager.Update()

        # Return if no device was found
        if device_manager.Devices().empty():
            print("no devices")
            return False

            # open the first openable device in the device manager's device list
        device_count = device_manager.Devices().size()
        for i in range(device_count):
            if device_manager.Devices()[i].IsOpenable():
                #print("open device")
                m_device = device_manager.Devices()[i].OpenDevice(peak.DeviceAccessType_Control)

                # Get NodeMap of the RemoteDevice for all accesses to the GenICam NodeMap tree
                m_node_map_remote_device = m_device.RemoteDevice().NodeMaps()[0]
                #print(m_node_map_remote_device)
                return True

    except Exception as e:
        # ...
        str_error = str(e)
        print(str_error)
    return False


def prepare_acquisition():
    global m_dataStream
    try:
        data_streams = m_device.DataStreams()
        if data_streams.empty():
            # no data streams available
            print("no data streams available")
            return False

        m_dataStream = m_device.DataStreams()[0].OpenDataStream()

        return True

    except Exception as e:
        # ...
        str_error = str(e)
        print(str_error)
    return False


def set_roi(x, y, width, height):
    try:
        # Get the minimum ROI and set it. After that there are no size restrictions anymore
        x_min = m_node_map_remote_device.FindNode("OffsetX").Minimum()
        y_min = m_node_map_remote_device.FindNode("OffsetY").Minimum()
        w_min = m_node_map_remote_device.FindNode("Width").Minimum()
        h_min = m_node_map_remote_device.FindNode("Height").Minimum()

        m_node_map_remote_device.FindNode("OffsetX").SetValue(x_min)
        m_node_map_remote_device.FindNode("OffsetY").SetValue(y_min)
        m_node_map_remote_device.FindNode("Width").SetValue(w_min)
        m_node_map_remote_device.FindNode("Height").SetValue(h_min)

        # Get the maximum ROI values
        x_max = m_node_map_remote_device.FindNode("OffsetX").Maximum()
        y_max = m_node_map_remote_device.FindNode("OffsetY").Maximum()
        w_max = m_node_map_remote_device.FindNode("Width").Maximum()
        h_max = m_node_map_remote_device.FindNode("Height").Maximum()

        if (x < x_min) or (y < y_min) or (x > x_max) or (y > y_max):
            return False
        elif (width < w_min) or (height < h_min) or ((x + width) > w_max) or ((y + height) > h_max):
            return False
        else:
            # Now, set final AOI
            m_node_map_remote_device.FindNode("OffsetX").SetValue(x)
            m_node_map_remote_device.FindNode("OffsetY").SetValue(y)
            m_node_map_remote_device.FindNode("Width").SetValue(width)
            m_node_map_remote_device.FindNode("Height").SetValue(height)

            return True
    except Exception as e:
        # ...
        str_error = str(e)
        print(str_error)
    return False


def alloc_and_announce_buffers():
    try:
        if m_dataStream:
            # Flush queue and prepare all buffers for revoking
            m_dataStream.Flush(peak.DataStreamFlushMode_DiscardAll)

            # Clear all old buffers
        for buffer in m_dataStream.AnnouncedBuffers():
            m_dataStream.RevokeBuffer(buffer)

        payload_size = m_node_map_remote_device.FindNode("PayloadSize").Value()

        # Get number of minimum required buffers
        num_buffers_min_required = m_dataStream.NumBuffersAnnouncedMinRequired()

        # Alloc buffers
        for count in range(num_buffers_min_required):
            buffer = m_dataStream.AllocAndAnnounceBuffer(payload_size)
            m_dataStream.QueueBuffer(buffer)

        return True
    except Exception as e:
        # ...
        str_error = str(e)
        print(str_error)
    return False


def start_acquisition(exposure_us, gain):
    try:
        # Set frame rate first so the camera knows the exposure-time ceiling.
        m_node_map_remote_device.FindNode("AcquisitionFrameRate").SetValue(25.0)
        m_node_map_remote_device.FindNode("ExposureTime").SetValue(float(exposure_us))
        m_node_map_remote_device.FindNode("Gain").SetValue(float(gain))
        # Force hardware gamma to 1.0 (linear) so software gamma LUT owns
        # all correction. If the node is absent, the camera is already linear.
        try:
            m_node_map_remote_device.FindNode("Gamma").SetValue(1.0)
        except Exception:
            pass

        actual_exp  = m_node_map_remote_device.FindNode("ExposureTime").Value()
        actual_fps  = m_node_map_remote_device.FindNode("AcquisitionFrameRate").Value()
        actual_gain = m_node_map_remote_device.FindNode("Gain").Value()
        pixel_fmt   = m_node_map_remote_device.FindNode("PixelFormat").CurrentEntry().SymbolicValue()
        print(f"[IDS] PixelFormat={pixel_fmt}  "
              f"ExposureTime={actual_exp:.0f}us (requested {exposure_us})  "
              f"FrameRate={actual_fps:.1f}fps  Gain={actual_gain:.2f}")

        m_dataStream.StartAcquisition(peak.AcquisitionStartMode_Default, peak.DataStream.INFINITE_NUMBER)
        m_node_map_remote_device.FindNode("TLParamsLocked").SetValue(1)
        m_node_map_remote_device.FindNode("AcquisitionStart").Execute()
        return True
    except Exception as e:
        str_error = str(e)
        print(str_error)
    return False


def _build_gamma_lut(gamma):
    inv = 1.0 / gamma
    return np.array([((i / 255.0) ** inv) * 255 for i in range(256)], dtype=np.uint8)


def pub_image(width, height, image_pub, gamma_lut):
    index = 0
    try:
        while not rospy.is_shutdown():
            
            
            # Get buffer from device's DataStream. Wait 5000 ms. The buffer is automatically locked until it is queued again.
            # dataStreamDescriptor = m_device.DataStreams()[0]

            # dataStream = dataStreamDescriptor.OpenDataStream();

            buffer = m_dataStream.WaitForFinishedBuffer(5000)
            '''
            if buffer.HasChunks():
               m_node_map_remote_device.UpdateChunkNodes(buffer)
               time = m_node_map_remote_device.FindNode("ChunkTimestamp").Value()
               print(time)
            else:
                print("no chunks")
            #current_time = time.time()
            #ts_ms = current_time * 1000000
            '''

            # Create IDS peak IPL image from buffer
            image = ids_peak_ipl.Image_CreateFromSizeAndBuffer(
                buffer.PixelFormat(),
                buffer.BasePtr(),
                buffer.Size(),
                buffer.Width(),
                buffer.Height()
            )
            image_processed = image.ConvertTo(ids_peak_ipl.PixelFormatName_RGB8, ids_peak_ipl.ConversionMode_HighQuality)
            image_numpy = image_processed.get_numpy_3D()
            if gamma_lut is not None:
                image_numpy = gamma_lut[image_numpy]
            #cv2.imshow("dist img", image_numpy)
            #cv2.waitKey()
            #h,  w = image_numpy.shape[:2]
            # Intrinsics for the RGB camera added by Shrutarv
            #mtx = np.asarray([[1.7896e+03,0,1.0089e+03],
            #[0,1.7910e+03,726.1455],
            #[0,0,1]])
            #dist = np.asarray([-0.1785,0.0844, 1.7583e-04,-2.2580e-04])
            #image_undist = cv2.undistort(image_numpy, mtx, dist, None, mtx)
            #image_undist = image_numpy
            #cv2.imshow("undist img", image_undist)
            #cv2.waitKey()
            #value = m_node_map_remote_device.FindNode("Timestamp")
            '''
            #m_node_map_remote_device.FindNode("TimerSelector").SetCurrentEntry("Timer0")
            m_node_map_remote_device.FindNode("TimerTriggerSource").SetCurrentEntry("AcquisitionStart")
            # Determine the current entry of TimerTriggerActivation (str)
            
            print(ueye.UEYEIMAGEINFO.u64TimestampDevice)# Queue buffer again
            '''
            m_dataStream.QueueBuffer(buffer)
            msg = numpy_to_imgmsg(image_numpy, "rgb8")
	
            #msg = bridge.cv2_to_imgmsg(image_numpy, encoding='passthrough')
            timestamp = rospy.Time.now()
            msg.header.stamp = timestamp
            #file = "/home/eventcamera/Images/" + str(index) + ".jpg"
            #path = "/home/eventcamera/Images/" + str(index) + ".jpg"
            #msg.data = bridge.cv2_to_imgmsg(np.asarray(image_processed.get_numpy_3D()))
            #img = ids_peak_ipl.ImageWriter.Write(file, image_processed)
            #img = cv2.imread(path, 0)
            #print(timestamp)
            #print("time in microseconds", ts_ms)
            image_pub.publish(msg)
            #print("checkpoint")
            index = index + 1

    except Exception as e:
        # ...
        str_error = str(e)
        print(str_error)


def main():

    image_pub = rospy.Publisher("/rgb/image_raw",Image, queue_size=10)
    rospy.init_node('ids_cam_driver')

    exposure_us = rospy.get_param('~exposure_us', 25000)
    gain        = rospy.get_param('~gain', 1.0)
    gamma       = rospy.get_param('~gamma', 2.2)
    width  = rospy.get_param('~width',  640)
    height = rospy.get_param('~height', 480)
    peak.Library.Initialize()

    # The uEye daemon may still be uploading firmware when this node starts.
    # Retry for up to 30 s before giving up.
    for attempt in range(30):
        if open_camera():
            break
        rospy.logwarn("IDS camera not ready yet (attempt %d/30), retrying in 1 s...", attempt + 1)
        time.sleep(1)
    else:
        rospy.logerr("unable to open IDS camera after 30 attempts")
        sys.exit(-1)

    if not prepare_acquisition():
        # error
        print("unable to prepare image acquisition")
        sys.exit(-2)

    #if not set_roi(16, 16, 128, 128):
        # error
     #   print("unable to set roi")
      #  sys.exit(-3)

    if not alloc_and_announce_buffers():
        # error
        print("unable to alloc")
        sys.exit(-4)

    if not start_acquisition(exposure_us, gain):
        # error
        print("unable to start acquisition")
        sys.exit(-5)

    gamma_lut = _build_gamma_lut(gamma) if gamma != 1.0 else None
    pub_image(width, height, image_pub, gamma_lut)
    peak.Library.Close()




    # Current time in a tuple format

    sys.exit(0)

if __name__ == '__main__':
    try:
        main()
    except rospy.ROSInterruptException:
        pass
