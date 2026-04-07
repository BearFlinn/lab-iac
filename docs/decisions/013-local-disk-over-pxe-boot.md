# ADR-013: Local Disk Installs Over PXE Boot for K8s Nodes

**Date:** 2026-04-05
**Status:** Accepted
**Supersedes:** [ADR-005](005-nfs-root-for-pxe-nodes.md) (NFS-Root for PXE-Booted Nodes)

## Context

ADR-005 planned for Inspiron, Optiplex, and Quanta to be diskless, PXE-booting from the R730xd with NFS root filesystems served from ZFS datasets. This required standing up a TFTP server, configuring DHCP boot options, building custom initramfs images, and managing NFS root exports — none of which exist yet.

In practice, all K8s nodes already have Debian installed on local drives and are accessible via SSH. The PXE infrastructure would add significant complexity (TFTP, DHCP relay, NFS root debugging, initramfs maintenance) for marginal benefit — the nodes aren't truly diskless, they have working local storage.

## Decision

All K8s nodes boot from local disk. No PXE/TFTP/NFS-root infrastructure will be built. Nodes are provisioned via the existing Ansible playbooks over SSH.

## Alternatives Considered

- **PXE boot with NFS root (ADR-005)** — Rejected. The complexity of the boot chain (TFTP + DHCP + NFS root + custom initramfs) isn't justified when every node already has a functional local OS. The ZFS snapshot benefits for root filesystems can be achieved with standard backup tooling instead.

## Consequences

- **Eliminates an entire infrastructure layer.** No TFTP server, no DHCP boot config, no NFS root exports, no initramfs builds. Fewer moving parts to debug.
- **Faster path to cluster standup.** The blocking dependency on PXE server setup is removed — nodes are ready for containerd + kubeadm now.
- **Lose centralized root filesystem management.** Can't snapshot/clone node root filesystems from the server side. Acceptable — Ansible reprovisioning from scratch is fast enough for a 4-node homelab.
- **Each node manages its own boot disk.** Disk failures require local replacement + reinstall rather than just re-PXEing. Acceptable given the small cluster size.
- **ADR-004 (ZFS + iSCSI for K8s storage) is unaffected.** iSCSI is still the plan for K8s PVC block storage — only the root filesystem delivery method changes.
