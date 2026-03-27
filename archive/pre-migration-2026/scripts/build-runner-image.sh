#!/usr/bin/env bash
set -euo pipefail

# Build and push custom GitHub Actions runner image
# This image extends the base runner with Helm and kubectl

REGISTRY="${REGISTRY:-10.0.0.226:32346}"
IMAGE_NAME="github-runner-dind"
TAG="${TAG:-latest}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$SCRIPT_DIR/../docker/github-runner"

echo "Building custom GitHub Actions runner image..."
echo "Registry: $REGISTRY"
echo "Image: $IMAGE_NAME:$TAG"
echo ""

# Build image
docker build -t "$REGISTRY/$IMAGE_NAME:$TAG" "$DOCKER_DIR"

# Push to registry
echo ""
echo "Pushing image to registry..."
docker push "$REGISTRY/$IMAGE_NAME:$TAG"

echo ""
echo "✅ Image built and pushed successfully!"
echo ""
echo "Image: $REGISTRY/$IMAGE_NAME:$TAG"
echo ""
echo "To use this image, update runner-deployment.yaml:"
echo "  image: $REGISTRY/$IMAGE_NAME:$TAG"
