#!/bin/bash
# Script to configure NFS mount for tower-pc storage on WSL2
# This script adds an fstab entry and mounts the NFS share

set -euo pipefail

# Configuration
NFS_SERVER="10.0.0.249"
NFS_EXPORT="/mnt/nfs-storage"
MOUNT_POINT="/mnt/tower-nfs"
MOUNT_OPTIONS="nolock,soft,_netdev"

echo "=== NFS Mount Configuration Script ==="
echo ""
echo "NFS Server: ${NFS_SERVER}"
echo "NFS Export: ${NFS_EXPORT}"
echo "Mount Point: ${MOUNT_POINT}"
echo "Mount Options: ${MOUNT_OPTIONS}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root (use sudo)"
  exit 1
fi

# Create mount point if it doesn't exist
if [ ! -d "${MOUNT_POINT}" ]; then
  echo "Creating mount point: ${MOUNT_POINT}"
  mkdir -p "${MOUNT_POINT}"
else
  echo "Mount point already exists: ${MOUNT_POINT}"
fi

# Check if fstab entry already exists
FSTAB_ENTRY="${NFS_SERVER}:${NFS_EXPORT} ${MOUNT_POINT} nfs ${MOUNT_OPTIONS} 0 0"
if grep -q "${NFS_SERVER}:${NFS_EXPORT}" /etc/fstab; then
  echo "Warning: fstab entry already exists for ${NFS_SERVER}:${NFS_EXPORT}"
  echo "Existing entry:"
  grep "${NFS_SERVER}:${NFS_EXPORT}" /etc/fstab
  echo ""
  read -p "Do you want to replace it? (y/n): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing old entry..."
    sed -i "\|${NFS_SERVER}:${NFS_EXPORT}|d" /etc/fstab
  else
    echo "Skipping fstab modification"
    SKIP_FSTAB=1
  fi
fi

# Add fstab entry if not skipped
if [ -z "${SKIP_FSTAB}" ]; then
  echo "Adding fstab entry..."
  echo "" >> /etc/fstab
  echo "# Tower PC NFS Storage" >> /etc/fstab
  echo "${FSTAB_ENTRY}" >> /etc/fstab
  echo "fstab entry added successfully"
fi

echo ""
echo "Verifying NFS server is accessible..."
if showmount -e "${NFS_SERVER}" > /dev/null 2>&1; then
  echo "✓ NFS server is accessible"
  echo ""
  echo "Available exports:"
  showmount -e "${NFS_SERVER}"
else
  echo "✗ Warning: Cannot reach NFS server at ${NFS_SERVER}"
  echo "  Make sure the server is running and accessible"
  exit 1
fi

echo ""
echo "Attempting to mount..."
if mount "${MOUNT_POINT}"; then
  echo "✓ Mount successful!"
  echo ""
  echo "Mount details:"
  mount | grep "${MOUNT_POINT}"
  echo ""
  echo "Testing write access..."
  TEST_FILE="${MOUNT_POINT}/.mount-test-$$"
  if echo "test" > "${TEST_FILE}" 2>/dev/null; then
    rm -f "${TEST_FILE}"
    echo "✓ Write access confirmed"
  else
    echo "✗ Warning: No write access (this might be expected depending on NFS permissions)"
  fi
else
  echo "✗ Mount failed"
  echo "Try mounting manually with: sudo mount ${MOUNT_POINT}"
  exit 1
fi

echo ""
echo "=== Configuration Complete ==="
echo "The NFS share is now mounted at ${MOUNT_POINT}"
echo "It will automatically mount on boot (if the network is available)"
