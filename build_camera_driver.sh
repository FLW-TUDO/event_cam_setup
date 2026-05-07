#!/bin/bash
# Build the camera_driver Docker image.
# Run once (or after any Dockerfile change).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="$SCRIPT_DIR/docker_context"

# ── Pre-flight: auto-extract uEye .deb files from .tgz if present ────────────
UEYE_TGZ=$(ls "$CTX"/ids-software-suite-linux-64-*.tgz 2>/dev/null | head -n1)
if [[ -n "$UEYE_TGZ" ]]; then
    UEYE_DEBS=(
        "ueye-api_4.96.1.2054_amd64.deb"
        "ueye-common_4.96.1.2054_amd64.deb"
        "ueye-driver-usb_4.96.1.2054_amd64.deb"
        "ueye-driver-eth_4.96.1.2054_amd64.deb"
        "ueye-drivers_4.96.1.2054_amd64.deb"
    )
    NEED_EXTRACT=0
    for f in "${UEYE_DEBS[@]}"; do
        [[ -f "$CTX/$f" ]] || { NEED_EXTRACT=1; break; }
    done
    if [[ $NEED_EXTRACT -eq 1 ]]; then
        echo "Extracting uEye .deb files from $(basename "$UEYE_TGZ")..."
        tar -xzf "$UEYE_TGZ" -C "$CTX" "${UEYE_DEBS[@]}"
        echo "Done."
    fi
fi

# ── Pre-flight: check all required files are present ─────────────────────────
#
# Download both from: https://en.ids-imaging.com/download-details/AB02491.html
#
#   1. IDS Software Suite 4.96.1 (Linux 64-bit, Debian):
#      ids-software-suite-linux-64-4.96.1-debian.tgz
#      Place in docker_context/ — this script extracts the .deb files automatically.
#
#   2. IDS Peak 2.4.0.0 with uEye Transport Layer (Linux 64-bit):
#      ids-peak-with-ueyetl-linux-x86-2.4.0.0-64.deb
#      Place in docker_context/

REQUIRED_FILES=(
    "ueye-api_4.96.1.2054_amd64.deb"
    "ueye-common_4.96.1.2054_amd64.deb"
    "ueye-driver-usb_4.96.1.2054_amd64.deb"
    "ueye-driver-eth_4.96.1.2054_amd64.deb"
    "ueye-drivers_4.96.1.2054_amd64.deb"
    "ids-peak-with-ueyetl-linux-x86-2.4.0.0-64.deb"
)

MISSING=()
for f in "${REQUIRED_FILES[@]}"; do
    [[ -f "$CTX/$f" ]] || MISSING+=("$f")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo ""
    echo "ERROR: The following required package files are missing from docker_context/:"
    echo ""
    for f in "${MISSING[@]}"; do
        echo "  - $f"
    done
    echo ""
    echo "Download both packages from:"
    echo "  https://en.ids-imaging.com/download-details/AB02491.html"
    echo ""
    echo "  1. IDS Software Suite 4.96.1 (Linux 64-bit, Debian):"
    echo "     ids-software-suite-linux-64-4.96.1-debian.tgz"
    echo "     Place in docker_context/ — this script will extract the .deb files."
    echo ""
    echo "  2. IDS Peak 2.4.0.0 with uEye Transport Layer (Linux 64-bit):"
    echo "     ids-peak-with-ueyetl-linux-x86-2.4.0.0-64.deb"
    echo "     Place in docker_context/"
    echo ""
    exit 1
fi

# ── Build ─────────────────────────────────────────────────────────────────────
echo "Building camera_driver Docker image..."
docker build \
    -f "$SCRIPT_DIR/Dockerfile_camera_driver" \
    -t camera_driver \
    "$SCRIPT_DIR"

echo ""
echo "Done. Run the container with:"
echo "  $SCRIPT_DIR/run_camera_driver.sh"
