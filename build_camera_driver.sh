#!/bin/bash
# Build the camera_driver Docker image for amd64 or arm64 (Jetson).
#
# Usage:
#   ./build_camera_driver.sh                  # native arch (auto-detected)
#   ./build_camera_driver.sh --arch arm64     # arm64 (cross-compile or native Jetson build)
#   ./build_camera_driver.sh --arch amd64     # force amd64
#
# Cross-compiling arm64 on an amd64 host requires QEMU:
#   sudo apt-get install qemu-user-static binfmt-support
#   docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
#   docker buildx create --use
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTX="$SCRIPT_DIR/docker_context"

# ── Parse arguments ──────────────────────────────────────────────────────────
TARGET_ARCH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch) TARGET_ARCH="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# Auto-detect native arch if not specified
if [[ -z "$TARGET_ARCH" ]]; then
    HOST_ARCH="$(uname -m)"
    case "$HOST_ARCH" in
        x86_64)  TARGET_ARCH="amd64" ;;
        aarch64) TARGET_ARCH="arm64" ;;
        *)
            echo "ERROR: Unsupported host architecture: $HOST_ARCH"
            echo "Pass --arch amd64 or --arch arm64 explicitly."
            exit 1
            ;;
    esac
    echo "Detected host architecture: ${HOST_ARCH} → building for ${TARGET_ARCH}"
else
    echo "Target architecture: ${TARGET_ARCH}"
fi

# ── IDS Peak filename normalisation ──────────────────────────────────────────
# IDS distributes different filenames per arch; normalise to ids-peak-<arch>.deb
# so the Dockerfile can use a single COPY pattern.
NORMALISED_PEAK="${CTX}/ids-peak-${TARGET_ARCH}.deb"

if [[ "$TARGET_ARCH" == "amd64" ]]; then
    PEAK_SRC=$(ls "$CTX"/ids-peak-with-ueyetl-linux-x86-*.deb 2>/dev/null | head -n1)
elif [[ "$TARGET_ARCH" == "arm64" ]]; then
    PEAK_SRC=$(ls "$CTX"/ids-peak-with-ueyetl-linux-aarch64-*.deb 2>/dev/null | head -n1)
else
    echo "ERROR: Unsupported target architecture: ${TARGET_ARCH}"
    exit 1
fi

if [[ -n "$PEAK_SRC" && "$PEAK_SRC" != "$NORMALISED_PEAK" ]]; then
    echo "Normalising IDS Peak package: $(basename "$PEAK_SRC") → ids-peak-${TARGET_ARCH}.deb"
    cp "$PEAK_SRC" "$NORMALISED_PEAK"
fi

# ── Pre-flight: auto-extract uEye .deb files from .tgz if present ────────────
UEYE_TGZ=$(ls "$CTX"/ids-software-suite-linux-64-*.tgz 2>/dev/null | head -n1)
if [[ -n "$UEYE_TGZ" ]]; then
    UEYE_DEBS=(
        "ueye-api_4.96.1.2054_${TARGET_ARCH}.deb"
        "ueye-common_4.96.1.2054_${TARGET_ARCH}.deb"
        "ueye-driver-usb_4.96.1.2054_${TARGET_ARCH}.deb"
        "ueye-driver-eth_4.96.1.2054_${TARGET_ARCH}.deb"
        "ueye-drivers_4.96.1.2054_${TARGET_ARCH}.deb"
    )
    NEED_EXTRACT=0
    for f in "${UEYE_DEBS[@]}"; do
        [[ -f "$CTX/$f" ]] || { NEED_EXTRACT=1; break; }
    done
    if [[ $NEED_EXTRACT -eq 1 ]]; then
        echo "Extracting uEye .deb files from $(basename "$UEYE_TGZ") for ${TARGET_ARCH}..."
        tar -xzf "$UEYE_TGZ" -C "$CTX" "${UEYE_DEBS[@]}"
        echo "Done."
    fi
fi

# ── Pre-flight: check all required arch-specific files are present ────────────
#
# Download from: https://en.ids-imaging.com/download-details/AB02491.html
#
#   amd64 (x86 workstation / Ubuntu 20/22/24):
#     1. IDS Software Suite 4.96.1 (Linux 64-bit, Debian):
#        ids-software-suite-linux-64-4.96.1-debian.tgz  (extracts ueye-*_amd64.deb)
#     2. IDS Peak 2.4.0.0 with uEye Transport Layer (Linux x86 64-bit):
#        ids-peak-with-ueyetl-linux-x86-2.4.0.0-64.deb
#
#   arm64 (Jetson / Ubuntu 20 or 22):
#     1. IDS Software Suite 4.96.1 (Linux ARM64, Debian):
#        ids-software-suite-linux-arm64-4.96.1-debian.tgz  (extracts ueye-*_arm64.deb)
#     2. IDS Peak 2.4.0.0 with uEye Transport Layer (Linux aarch64):
#        ids-peak-with-ueyetl-linux-aarch64-2.4.0.0-64.deb
#
# Place both downloads in docker_context/ before running this script.

REQUIRED_FILES=(
    "ueye-api_4.96.1.2054_${TARGET_ARCH}.deb"
    "ueye-common_4.96.1.2054_${TARGET_ARCH}.deb"
    "ueye-driver-usb_4.96.1.2054_${TARGET_ARCH}.deb"
    "ueye-driver-eth_4.96.1.2054_${TARGET_ARCH}.deb"
    "ueye-drivers_4.96.1.2054_${TARGET_ARCH}.deb"
    "ids-peak-${TARGET_ARCH}.deb"
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
    echo "Download both packages for ${TARGET_ARCH} from:"
    echo "  https://en.ids-imaging.com/download-details/AB02491.html"
    echo ""
    if [[ "$TARGET_ARCH" == "amd64" ]]; then
        echo "  1. IDS Software Suite 4.96.1 (Linux 64-bit, Debian):"
        echo "     ids-software-suite-linux-64-4.96.1-debian.tgz"
        echo "     Place in docker_context/ — this script will extract the .deb files."
        echo ""
        echo "  2. IDS Peak 2.4.0.0 with uEye Transport Layer (Linux x86 64-bit):"
        echo "     ids-peak-with-ueyetl-linux-x86-2.4.0.0-64.deb"
    else
        echo "  1. IDS Software Suite 4.96.1 (Linux ARM64, Debian):"
        echo "     ids-software-suite-linux-arm64-4.96.1-debian.tgz"
        echo "     Place in docker_context/ — this script will extract the .deb files."
        echo ""
        echo "  2. IDS Peak 2.4.0.0 with uEye Transport Layer (Linux aarch64):"
        echo "     ids-peak-with-ueyetl-linux-aarch64-2.4.0.0-64.deb"
    fi
    echo ""
    exit 1
fi

# ── Determine if cross-compilation is needed ─────────────────────────────────
HOST_ARCH_NORM="amd64"
[[ "$(uname -m)" == "aarch64" ]] && HOST_ARCH_NORM="arm64"

CROSS_COMPILE=0
if [[ "$TARGET_ARCH" != "$HOST_ARCH_NORM" ]]; then
    CROSS_COMPILE=1
    echo "Cross-compiling ${TARGET_ARCH} on ${HOST_ARCH_NORM} host — requires QEMU + buildx."
    if ! docker buildx version &>/dev/null; then
        echo ""
        echo "ERROR: docker buildx not available. Install Docker Engine >= 19.03 with BuildKit."
        exit 1
    fi
    if ! docker run --rm --platform "linux/${TARGET_ARCH}" alpine uname -m &>/dev/null 2>&1; then
        echo ""
        echo "ERROR: Cannot run linux/${TARGET_ARCH} containers. Set up QEMU first:"
        echo "  sudo apt-get install qemu-user-static binfmt-support"
        echo "  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes"
        echo "  docker buildx create --use"
        exit 1
    fi
fi

# ── Build ─────────────────────────────────────────────────────────────────────
echo ""
echo "Building camera_driver:latest for linux/${TARGET_ARCH}..."

if [[ $CROSS_COMPILE -eq 1 ]]; then
    docker buildx build \
        --platform "linux/${TARGET_ARCH}" \
        --load \
        --build-arg TARGETARCH="${TARGET_ARCH}" \
        -f "$SCRIPT_DIR/Dockerfile_camera_driver" \
        -t camera_driver \
        "$SCRIPT_DIR"
else
    docker build \
        --platform "linux/${TARGET_ARCH}" \
        --build-arg TARGETARCH="${TARGET_ARCH}" \
        -f "$SCRIPT_DIR/Dockerfile_camera_driver" \
        -t camera_driver \
        "$SCRIPT_DIR"
fi

echo ""
echo "Done. Image tagged: camera_driver:latest (linux/${TARGET_ARCH})"
echo "Run with: $SCRIPT_DIR/run_camera_driver.sh"
