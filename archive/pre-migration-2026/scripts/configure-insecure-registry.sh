#!/usr/bin/env bash
#
# Configure containerd to use insecure self-hosted registry
# This script safely adds registry configuration without breaking existing config
#
# Usage:
#   ./configure-insecure-registry.sh <registry-endpoint>
#   Example: ./configure-insecure-registry.sh 10.0.0.226:32346

set -euo pipefail

REGISTRY_ENDPOINT="${1:-10.0.0.226:32346}"
CONFIG_FILE="/etc/containerd/config.toml"
BACKUP_FILE="${CONFIG_FILE}.backup-$(date +%Y%m%d-%H%M%S)"

echo "==> Configuring containerd for insecure registry: $REGISTRY_ENDPOINT"

# Backup current config
echo "==> Creating backup: $BACKUP_FILE"
sudo cp "$CONFIG_FILE" "$BACKUP_FILE"

# Create temporary config with registry settings
TEMP_CONFIG=$(mktemp)
cat > "$TEMP_CONFIG" << EOF
# Registry configuration for $REGISTRY_ENDPOINT
[plugins."io.containerd.grpc.v1.cri".registry]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."$REGISTRY_ENDPOINT"]
      endpoint = ["http://$REGISTRY_ENDPOINT"]
  [plugins."io.containerd.grpc.v1.cri".registry.configs]
    [plugins."io.containerd.grpc.v1.cri".registry.configs."$REGISTRY_ENDPOINT"]
      [plugins."io.containerd.grpc.v1.cri".registry.configs."$REGISTRY_ENDPOINT".tls]
        insecure_skip_verify = true
EOF

# Check if registry config already exists
if grep -q "registry.mirrors.\"$REGISTRY_ENDPOINT\"" "$CONFIG_FILE"; then
    echo "==> Registry $REGISTRY_ENDPOINT already configured, skipping"
    rm "$TEMP_CONFIG"
    exit 0
fi

# Merge the config - append our settings before the last closing bracket
sudo sed -i.tmp '/^[[:space:]]*\[plugins\."io\.containerd\.grpc\.v1\.cri"\.registry\.mirrors\]/,/^[[:space:]]*\[plugins\."io\.containerd\.grpc\.v1\.cri"\.registry\.configs\]/{
    /\[plugins\."io\.containerd\.grpc\.v1\.cri"\.registry\.mirrors\]/a\
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."'$REGISTRY_ENDPOINT'"]\
      endpoint = ["http://'$REGISTRY_ENDPOINT'"]
}' "$CONFIG_FILE"

sudo sed -i.tmp '/^[[:space:]]*\[plugins\."io\.containerd\.grpc\.v1\.cri"\.registry\.configs\]/a\
    [plugins."io.containerd.grpc.v1.cri".registry.configs."'$REGISTRY_ENDPOINT'"]\
      [plugins."io.containerd.grpc.v1.cri".registry.configs."'$REGISTRY_ENDPOINT'".tls]\
        insecure_skip_verify = true' "$CONFIG_FILE"

# Fix CNI bin_dir path (common issue)
echo "==> Fixing CNI binary path..."
sudo sed -i 's|bin_dir = "/usr/lib/cni"|bin_dir = "/opt/cni/bin"|g' "$CONFIG_FILE"

# Verify the config is valid
echo "==> Validating containerd config..."
if ! sudo containerd config dump > /dev/null 2>&1; then
    echo "ERROR: Invalid containerd config! Restoring backup..."
    sudo cp "$BACKUP_FILE" "$CONFIG_FILE"
    rm "$TEMP_CONFIG"
    exit 1
fi

echo "==> Restarting containerd..."
sudo systemctl restart containerd

# Wait for containerd to be ready
sleep 3

if sudo systemctl is-active --quiet containerd; then
    echo "==> SUCCESS! Containerd configured for insecure registry: $REGISTRY_ENDPOINT"
else
    echo "ERROR: Containerd failed to start! Restoring backup..."
    sudo cp "$BACKUP_FILE" "$CONFIG_FILE"
    sudo systemctl restart containerd
    exit 1
fi

rm "$TEMP_CONFIG"
