#!/bin/bash
# Build the camera_driver Docker image.
# Run once (or after any Dockerfile change).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Building camera_driver Docker image..."
docker build \
    -f "$SCRIPT_DIR/Dockerfile_camera_driver" \
    -t camera_driver \
    "$SCRIPT_DIR"

echo ""
echo "Done. Run the container with:"
echo "  $SCRIPT_DIR/run_camera_driver.sh"
