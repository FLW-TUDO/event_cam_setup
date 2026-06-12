#!/bin/bash
# Run this ONCE on the Ubuntu 22 host (NOT inside Docker).
# Installs udev rules so DVXplorer and IDS cameras are accessible without root.
set -e

echo "Installing camera udev rules on host..."

# iniVation vendor ID for DVXplorer / DAVIS cameras
RULES_FILE="/etc/udev/rules.d/65-inivation.rules"

sudo tee "$RULES_FILE" > /dev/null <<'EOF'
# DVXplorer (iniVation)
SUBSYSTEM=="usb", ATTRS{idVendor}=="152a", MODE="0666", GROUP="plugdev"
# DAVIS 240/346
SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="0666", GROUP="plugdev"
EOF

# IDS Imaging cameras (uEye USB and USB3 Vision, VID 0x1409)
IDS_RULES_FILE="/etc/udev/rules.d/66-ids-cameras.rules"
sudo tee "$IDS_RULES_FILE" > /dev/null <<'EOF'
# IDS Imaging Development Systems GmbH (uEye USB and USB3 cameras)
SUBSYSTEM=="usb", ATTRS{idVendor}=="1409", MODE="0666", GROUP="plugdev"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

# Add current user to plugdev if not already in it
if ! groups "$USER" | grep -q plugdev; then
    sudo usermod -aG plugdev "$USER"
    echo "Added $USER to plugdev group. Please log out and back in (or reboot) for this to take effect."
fi

echo "udev rules installed:"
echo "  $RULES_FILE  (iniVation DVXplorer/DAVIS)"
echo "  $IDS_RULES_FILE  (IDS Imaging cameras)"
echo "Plug in your cameras now (or re-plug them)."
