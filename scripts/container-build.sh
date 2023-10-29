#!/usr/bin/env bash
set -euo pipefail

# container-build.sh
# Builds the staging tarball inside an Alpine container. This prepares the payload
# that can be used later on macOS to create a signed/notarized .pkg.

IMAGE_NAME="homebridge-macos-pkg-builder:latest"

docker build -t "$IMAGE_NAME" -f scripts/Dockerfile .

# Run container, mount current repo and extract build artifact to host
rm -rf build || true
docker run --rm -v "$(pwd)":/work/src "$IMAGE_NAME" bash -lc "cd /work/src && bash build.sh --staging-only"

echo "Staging build completed. See build/homebridge-staging.tar.gz"
