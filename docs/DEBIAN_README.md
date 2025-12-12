# Debian Base Image - Packer Configuration

This Packer configuration builds a base Debian 12 (Bookworm) image using QEMU/KVM.

## Files

- `debian-base.pkr.hcl` - Main Packer configuration
- `http/preseed.cfg` - Automated Debian installation configuration
- `vars/debian-base.pkrvars.hcl` - Customizable variables

## Prerequisites

- Packer installed
- QEMU/KVM installed and configured
- Sufficient disk space (~5GB for build artifacts)

## Quick Start

### Initialize Packer

```bash
cd /home/bearf/Projects/lab-iac/packer
packer init debian-base.pkr.hcl
```

### Build the Image

```bash
# Build with default values
packer build debian-base.pkr.hcl

# Build with custom variables
packer build -var-file=vars/debian-base.pkrvars.hcl debian-base.pkr.hcl
```

### Validate Configuration

```bash
packer validate debian-base.pkr.hcl
```

## Configuration Details

### Default Settings

- **OS**: Debian 13.2.0 (Trixie) - Latest stable as of December 2025
- **Disk Size**: 20GB
- **Memory**: 2048MB
- **CPUs**: 2
- **Default User**: debian/debian (with sudo access)

### Installed Packages

The base image includes:
- SSH server
- Cloud-init
- QEMU guest agent
- Basic utilities (curl, wget, vim, git)
- Build essentials

### Customization

Edit `vars/debian-base.pkrvars.hcl` to customize:
- VM resources (CPU, memory, disk)
- Debian version
- SSH credentials
- VM name

### Security Notes

- Default credentials are `debian/debian` - **change these for production!**
- The debian user has passwordless sudo access
- SSH is enabled by default

## Output

After building, you'll find:
- QCOW2 image in `output-debian-base/`
- Build manifest in `manifest.json`

## Next Steps

You can:
1. Convert the QCOW2 image to other formats
2. Upload to your virtualization platform
3. Use as a base for further customization
4. Create templates for cloud-init enabled VMs
