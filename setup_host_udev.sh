#!/bin/bash
# Run this ONCE on the host (NOT inside Docker).
# Installs udev rules so DVXplorer, IDS and Prophesee cameras are accessible
# without root. Works on Debian/Ubuntu (plugdev) and Arch/Manjaro (uaccess).
set -e

echo "Installing camera udev rules on host..."

# Debian/Ubuntu ship a "plugdev" group and expect devices to be owned by it.
# Arch/Manjaro have no such group and instead rely on the uaccess tag, where
# systemd-logind grants an ACL to the user on the active seat. Emit GROUP=
# only where the group exists, and always tag uaccess: on Arch that gives the
# logged-in user access immediately, with MODE=0666 as the fallback for
# headless/Docker use.
if getent group plugdev > /dev/null; then
    GRP='GROUP="plugdev", '
    echo "Found plugdev group - rules will assign devices to it."
else
    GRP=''
    echo "No plugdev group (Arch/Manjaro) - relying on uaccess tag + MODE=0666."
fi

PERMS="MODE=\"0666\", ${GRP}TAG+=\"uaccess\""

# iniVation vendor ID for DVXplorer / DAVIS cameras
RULES_FILE="/etc/udev/rules.d/65-inivation.rules"

sudo tee "$RULES_FILE" > /dev/null <<EOF
# DVXplorer (iniVation)
SUBSYSTEM=="usb", ATTRS{idVendor}=="152a", $PERMS
# DAVIS 240/346
SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", $PERMS
EOF

# IDS Imaging cameras (uEye USB and USB3 Vision, VID 0x1409).
# The whole vendor ID is matched, so the UE-39B0XCP (1409:8e00) is covered.
IDS_RULES_FILE="/etc/udev/rules.d/66-ids-cameras.rules"
sudo tee "$IDS_RULES_FILE" > /dev/null <<EOF
# IDS Imaging Development Systems GmbH (uEye USB and USB3 cameras)
SUBSYSTEM=="usb", ATTRS{idVendor}=="1409", $PERMS
EOF

# Prophesee event cameras (EVK4 etc.)
PROPHESEE_RULES_FILE="/etc/udev/rules.d/67-prophesee.rules"
sudo tee "$PROPHESEE_RULES_FILE" > /dev/null <<EOF
# Prophesee event-based cameras
SUBSYSTEM=="usb", ATTRS{idVendor}=="152a", ATTRS{idProduct}=="84[0-1]?", $PERMS
# Cypress FX3 (EVK4 enumerates as 04b4:00f4/00f5)
SUBSYSTEM=="usb", ATTRS{idVendor}=="04b4", ATTRS{idProduct}=="00f[4-5]", $PERMS
SUBSYSTEM=="usb", ATTRS{idVendor}=="31f7", ATTRS{idProduct}=="000[3-4]", $PERMS
EOF

# Fail loudly if a rule file is malformed instead of silently not applying.
if command -v udevadm > /dev/null && udevadm verify --help > /dev/null 2>&1; then
    udevadm verify "$RULES_FILE" "$IDS_RULES_FILE" "$PROPHESEE_RULES_FILE"
fi

sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb --action=add

# On Debian/Ubuntu, membership in plugdev is what grants access.
if [ -n "$GRP" ] && ! id -nG "$USER" | tr ' ' '\n' | grep -qx plugdev; then
    sudo usermod -aG plugdev "$USER"
    echo "Added $USER to plugdev. Log out and back in (or reboot) to apply."
fi

echo "udev rules installed:"
echo "  $RULES_FILE  (iniVation DVXplorer/DAVIS)"
echo "  $IDS_RULES_FILE  (IDS Imaging, incl. UE-39B0XCP 1409:8e00)"
echo "  $PROPHESEE_RULES_FILE  (Prophesee EVK4)"
echo "Plug in your cameras now (or re-plug them)."
