# Calibration Pipeline — RGB + Stereo Event Camera (Ubuntu 22, Docker)

Complete workflow from recording to the final `camchain.yaml` calibration file.

**Setup:**
- Ubuntu 22 PC (this machine) — all steps run here via Docker
- Cameras: IDS RGB + 2× DVXplorer (left `DXA00420`, right `DXA00247`)
- Docker images: `camera_driver` (ROS Noetic + all drivers), `kalibr`
- e2calib: `~/event_camera/e2calib/` (virtualenv at `e2calib/e2calib/`)

---

## One-Time Host Setup

Run once after connecting cameras to this Ubuntu 22 PC:

```bash
sudo bash ~/event_camera/setup_host_udev.sh
```

---

## Step 1 — Record Calibration Bag

Launch the camera driver container:

```bash
bash ~/event_camera/run_camera_driver.sh
```

Inside the container, open **3 terminals** (`docker exec -it <container> bash` for extra terminals):

**Terminal 1 — ROS core:**
```bash
source /catkin_ws/devel/setup.bash
roscore
```

**Terminal 2 — Launch cameras:**
```bash
source /catkin_ws/devel/setup.bash
roslaunch /workspace/RGB_Event_cam_system/RGB_event_cam_stereo.launch
```

**Terminal 3 — Record:**
```bash
mkdir -p /data/new_calib
rosbag record \
  /dvxplorer_left/events \
  /dvxplorer_right/events \
  /rgb/image_raw \
  -O /data/new_calib/events_only.bag
```

> **Critical:** Move the checkerboard **slowly** (hold each pose ~0.5 s). Fast motion = blurry
> reconstructed frames = Kalibr cannot detect corners. Cover the full FOV: corners, center,
> near, far, tilted poses. Record for ~3 minutes.

Stop recording with `Ctrl+C`. Exit the container.

---

## Step 2 — Convert Event Topics to H5

Still inside the camera_driver container (or re-enter it):

```bash
source /catkin_ws/devel/setup.bash
pip3 install h5py --quiet

# Left camera
python3 /workspace/e2calib/python/convert.py \
  --input_file  /data/new_calib/events_only.bag \
  --topic       /dvxplorer_left/events \
  --output_file /data/new_calib/events_left.h5

# Right camera
python3 /workspace/e2calib/python/convert.py \
  --input_file  /data/new_calib/events_only.bag \
  --topic       /dvxplorer_right/events \
  --output_file /data/new_calib/events_right.h5
```

**Output:** `events_left.h5`, `events_right.h5`

---

## Step 3 — Reconstruct Event Frames (e2calib)

Run on the **host** (Ubuntu 22) using the local e2calib virtualenv:

```bash
cd ~/event_camera/e2calib
source e2calib/bin/activate

# Left camera → cam1/
python python/offline_reconstruction.py \
  --h5file    ~/event_camera/calibration_data/new_calib/events_left.h5 \
  --freq_hz   5 \
  --output_folder ~/event_camera/calibration_data/new_calib/reconstructed \
  --use_gpu

mv ~/event_camera/calibration_data/new_calib/reconstructed/e2calib \
   ~/event_camera/calibration_data/new_calib/reconstructed/cam1

# Right camera → cam2/
python python/offline_reconstruction.py \
  --h5file    ~/event_camera/calibration_data/new_calib/events_right.h5 \
  --freq_hz   5 \
  --output_folder ~/event_camera/calibration_data/new_calib/reconstructed \
  --use_gpu

mv ~/event_camera/calibration_data/new_calib/reconstructed/e2calib \
   ~/event_camera/calibration_data/new_calib/reconstructed/cam2

deactivate
```

> Use `--freq_hz 5` for calibration (low enough to get sharp frames). Remove `--use_gpu`
> if not available.

**Output:** `reconstructed/cam1/` and `reconstructed/cam2/` — timestamped PNG images

---

## Step 4 — Extract RGB Frames from Bag

Inside the camera_driver container:

```bash
source /catkin_ws/devel/setup.bash
mkdir -p /data/new_calib/reconstructed/cam0

python3 - <<'EOF'
import rosbag
from cv_bridge import CvBridge
import cv2, os

bridge = CvBridge()
out = '/data/new_calib/reconstructed/cam0'
bag = rosbag.Bag('/data/new_calib/events_only.bag')

for i, (topic, msg, t) in enumerate(bag.read_messages(topics=['/rgb/image_raw'])):
    img = bridge.imgmsg_to_cv2(msg, 'bgr8')
    cv2.imwrite(os.path.join(out, f'{t.to_nsec():020d}.png'), img)

bag.close()
print(f'Done — extracted {i+1} frames')
EOF
```

**Output:** `reconstructed/cam0/` — RGB frames named by nanosecond timestamp

---

## Step 5 — Create Kalibr Image Bag

Inside the **Kalibr Docker**:

```bash
docker run -it --rm \
  -v ~/event_camera/calibration_data:/data \
  kalibr

# Inside Kalibr container:
source /catkin_ws/devel/setup.bash

# Folder structure must be:
#   /data/new_calib/reconstructed/cam0/  ← RGB
#   /data/new_calib/reconstructed/cam1/  ← left event recon
#   /data/new_calib/reconstructed/cam2/  ← right event recon

/catkin_ws/devel/lib/kalibr/kalibr_bagcreater \
  --folder /data/new_calib/reconstructed \
  --output-bag /data/new_calib/kalibr_images.bag
```

**Output:** `kalibr_images.bag`

---

## Step 6 — Run Kalibr Calibration

Inside the **Kalibr Docker** (same session):

```bash
cd /data/new_calib

/catkin_ws/devel/lib/kalibr/kalibr_calibrate_cameras \
  --bag    /data/new_calib/kalibr_images.bag \
  --target /workspace/calibration_data/kalibr_run/checkerboard_8x6_5cm.yaml \
  --models pinhole-radtan pinhole-radtan pinhole-radtan \
  --topics /cam0/image_raw /cam1/image_raw /cam2/image_raw \
  --bag-freq 4.0 \
  --show-extraction \
  --verbose
```

> If reprojection error is high (> 1 px) for the event cameras, try `omni-radtan` instead
> of `pinhole-radtan` for those two models.

---

## Output Files

Kalibr writes to the current directory (`/data/new_calib/`):

| File | Description |
|------|-------------|
| `camchain.yaml` | **Final calibration** — intrinsics + extrinsics for all cameras |
| `results-cam.txt` | Human-readable summary with reprojection errors |
| `report-cam.pdf` | Visual report with corner detections and residuals |

Copy `camchain.yaml` out of the container:
```bash
# On the host (outside Docker):
docker cp <container_id>:/data/new_calib/camchain.yaml ~/event_camera/calibration_data/
```

Target reprojection error: **< 0.5 px** per camera.

---

## Calibration Target YAML

Located at:
```
~/event_camera/calibration_data/kalibr_run/checkerboard_8x6_5cm.yaml
```

Contents (verify against your physical board):
```yaml
target_type: 'checkerboard'
targetCols: 8
targetRows: 6
rowSpacingMeters: 0.05
colSpacingMeters: 0.05
```

> `targetCols` / `targetRows` = **inner corners** (not squares).
> An 8×6 inner-corner board has 9×7 squares.

---

## Quick Reference — Docker Commands

```bash
# Start camera driver container
bash ~/event_camera/run_camera_driver.sh

# Open extra terminal in running container
docker exec -it $(docker ps -q --filter ancestor=camera_driver) bash

# Start Kalibr container
docker run -it --rm \
  -v ~/event_camera/calibration_data:/data \
  -v ~/event_camera:/workspace \
  kalibr
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| "No corners extracted" | Blurry reconstructed frames | Move board slower; reduce `--freq_hz` |
| Few corners detected | Wrong board size in YAML | Recount inner corners on physical board |
| High reprojection error | Motion blur in RGB frames | Record at lower speed |
| IDS camera not found | Missing udev rules or USB permission | Re-run `setup_host_udev.sh`, replug USB |
| DVXplorer not found | Wrong serial or udev missing | Check serials: `DXA00420` (left/master), `DXA00247` (right/slave) |
