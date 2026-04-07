# ADR-015: Dynamic Storage Provisioning via democratic-csi

**Date:** 2026-04-05
**Status:** Accepted
**Refines:** [ADR-004](004-zfs-iscsi-for-k8s-storage.md) (ZFS + iSCSI for K8s Block Storage)

## Context

ADR-004 established that K8s PVCs should use iSCSI backed by ZFS zvols for latency-sensitive workloads, with NFS off MergerFS for bulk data. The remaining question was whether to provision PVs manually or use a CSI driver for dynamic provisioning. Manual PV creation is operationally fragile in a setup where the operator is self-described as "forgetful to a fault" and automation is strongly preferred.

The R730xd has two storage tiers: a ZFS raidz1 pool (3×2TB, ~3.6TB usable) for random I/O, and a MergerFS/SnapRAID pool (5×3TB data + 2×4TB parity, ~15TB usable) for bulk/read-heavy workloads.

## Decision

Use democratic-csi to dynamically provision both storage classes from the R730xd:

- **iSCSI StorageClass (ZFS zvols):** For databases, queues, and anything fsync-heavy or random-I/O sensitive. Backed by the ZFS pool.
- **NFS StorageClass (MergerFS):** For media, bulk files, and read-heavy workloads where multiple pods need concurrent access. Backed by the MergerFS pool — not ZFS — to keep random I/O off the parity array.

democratic-csi handles both protocols from one driver, creating zvols/exports on demand via the R730xd's ZFS and NFS APIs.

## Alternatives Considered

- **Manual PV creation** — Simpler initially, but every new PVC requires SSH-ing into the R730xd to create a zvol/export and writing a PV manifest. Guaranteed to be forgotten or done inconsistently.
- **NFS subdir provisioner (for NFS class)** — Lighter than democratic-csi for NFS-only, but doesn't handle iSCSI. Running two separate provisioners adds complexity for no benefit.

## Consequences

- **Zero manual steps for storage.** Developers (and Flux) create a PVC, democratic-csi provisions the backing storage automatically. Matches the "nothing manual" operational model.
- **Two StorageClasses to choose from.** Workload authors must pick `iscsi-zfs` or `nfs-mergerfs` — wrong choice means either wasted ZFS capacity or poor random I/O performance. Default StorageClass should be iSCSI since most workloads benefit from it, with NFS used explicitly for bulk/read-heavy cases.
- **democratic-csi requires API access to the R730xd.** Runs as a controller in K8s and SSH/APIs into the storage server. Adds a dependency — if R730xd is unreachable, no new PVs can be created (existing ones keep working).
- **MergerFS NFS exports need a stable path convention.** democratic-csi will create subdirectories under a base export. The NFS server role on the R730xd must be configured to allow this.
