# Scripts

Shell scripts for infrastructure setup. All use `set -euo pipefail` and are idempotent.

Previous K8s cluster scripts are in `archive/pre-migration-2026/scripts/`.

| Script | Purpose |
|--------|---------|
| `build-r730xd-iso.sh` | Build preseeded Debian 13 ISO for R730xd automated install |
| `configure-r730xd-jbod.sh` | Configure R730xd PERC H730 controller for JBOD mode via iDRAC racadm |
| `build-jumpbox-image.sh` | Build Debian Trixie image for the jumpbox (AMD C60 mini PC) |
