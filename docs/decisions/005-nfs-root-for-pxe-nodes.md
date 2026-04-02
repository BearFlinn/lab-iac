# ADR-005: NFS-Root (off ZFS) for PXE-Booted Nodes

**Date:** 2026-04-02
**Status:** Accepted

## Context

The K8s nodes (Inspiron, Optiplex, Quanta) will be diskless, PXE-booting from the R730xd. After TFTP delivers the kernel and initramfs, the node needs a root filesystem. The R730xd has a ZFS pool (3×2TB) available for this. The question is whether to serve root filesystems via NFS or iSCSI.

On a 1GbE network, both protocols saturate the link at roughly the same throughput. iSCSI has lower latency for small random I/O, but PXE root filesystems are mostly read-heavy after boot — steady-state K8s node operation generates minimal root filesystem I/O.

## Decision

Serve PXE node root filesystems via NFS exports from ZFS datasets on the R730xd. Use iSCSI only for K8s PVCs (see ADR-004).

## Alternatives Considered

- **iSCSI zvols for root** — Lower latency on random I/O, but adds significant boot chain complexity: the initramfs needs an iSCSI initiator (open-iscsi), must discover and log into targets before mounting root, and failure modes are harder to debug. The performance difference is negligible for root filesystem workloads on 1GbE.

## Consequences

- **Simpler boot chain.** Kernel nfsroot support is mature and well-documented. No initramfs iSCSI initiator needed — just `root=/dev/nfs` in kernel args.
- **ZFS snapshots still available.** Each node gets a ZFS dataset exported via NFS. Snapshot before OS updates, clone for new nodes.
- **Easier debugging.** NFS root can be inspected from the server side by browsing the exported directory. iSCSI zvols require mounting the block device.
- **Marginally higher latency on package installs / heavy metadata ops.** Acceptable tradeoff — these are infrequent operations on K8s worker nodes.
