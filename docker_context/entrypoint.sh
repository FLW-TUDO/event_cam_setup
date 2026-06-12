#!/bin/bash
# Container entrypoint: start the IDS uEye USB daemon, wait until the camera
# is fully enumerated and visible to IDS Peak, then drop to bash.
set -e

mkdir -p /var/run/ueyed

# /dev/bus/usb nodes are created root:root 0600 by the host kernel.
# The uEye daemon drops to the 'ueyed' user and needs read/write access.
chmod -R a+rw /dev/bus/usb 2>/dev/null || true

/opt/ids/ueye/bin/ueyeusbd \
    -c /etc/ids/ueye/ueyeusbd.conf \
    -P /var/run/ueyed/ueyeusbd.pid &

# Poll until IDS Peak actually sees a device.
# Re-apply chmod each second to cover freshly re-enumerated USB nodes.
echo "[entrypoint] Waiting for IDS RGB camera..."
for i in $(seq 1 30); do
    sleep 1
    chmod -R a+rw /dev/bus/usb 2>/dev/null || true
    n=$(python3 - 2>/dev/null <<'PYEOF'
try:
    from ids_peak import ids_peak as peak
    peak.Library.Initialize()
    dm = peak.DeviceManager.Instance()
    dm.Update()
    print(dm.Devices().size())
    peak.Library.Close()
except Exception:
    print(0)
PYEOF
)
    if [ "${n:-0}" -gt 0 ]; then
        echo "[entrypoint] IDS camera ready (${n} device(s) found after ${i}s)"
        break
    fi
done

if [ "${n:-0}" -eq 0 ]; then
    echo "[entrypoint] WARNING: IDS camera not detected after 30s — continuing anyway"
fi

source /catkin_ws/devel/setup.bash
exec bash
