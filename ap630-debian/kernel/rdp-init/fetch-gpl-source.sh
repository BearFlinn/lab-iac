#!/bin/bash
# Fetch BCM4908 RDP GPL source from asuswrt-merlin.ng for porting.
# These files are needed to write the RDP init kernel module.
#
# The U-Boot version is self-contained with all constants inline,
# making it the best base for porting (vs the kernel version which
# depends on hundreds of KB of generated headers).
#
# Usage: bash fetch-gpl-source.sh [output_dir]

set -euo pipefail
OUT="${1:-/tmp/rdp-gpl-source}"
mkdir -p "$OUT/uboot" "$OUT/firmware" "$OUT/kernel-driver"

REPO="RMerl/asuswrt-merlin.ng"

fetch() {
    local path="$1" dest="$2"
    echo -n "  $dest... "
    gh api "repos/$REPO/contents/$path" --jq '.content' 2>/dev/null | base64 -d > "$dest" 2>/dev/null
    local sz=$(wc -c < "$dest")
    if [ "$sz" -gt 0 ]; then echo "${sz} bytes"; else echo "FAILED"; fi
}

echo "=== U-Boot RDP init (self-contained, best for porting) ==="
UBOOT="release/src-rt-5.04axhnd.675x/bootloaders/u-boot-2019.07/arch/arm/mach-bcmbca/rdp"
for f in data_path_init.c data_path_init.h access_macros.h rdp_map.h \
         rdp_subsystem_common.h rdp_drv_bbh.h rdp_drv_bpm.h rdp_drv_sbpm.h \
         rdp_drv_ih.h rdp_bbh.h rdp_bpm.h rdp_dma.h rdp_sbpm.h rdp_runner.h \
         rdd_ih_defs.h rdd_runner_defs.h rdd_runner_defs_auto.h \
         rdd_data_structures.h rdd_data_structures_auto.h \
         rdd_defs.h rdd.h rdd_init.h rdd_init.c rdd_common.c \
         rdpa_types.h rdpa_config.h rdp_mm.h bcm_pkt_lengths.h \
         packing.h bdmf_data_types.h bdmf_errno.h bl_os_wraper.h \
         rdp_drv_bbh.c rdp_drv_bpm.c rdp_drv_sbpm.c rdp_drv_ih.c \
         rdp_bbh_arrays.c rdp_dma_arrays.c rdd_tm.c rdd_tm.h \
         rdd_cpu.c rdd_cpu.h rdd_common.h rdd_platform.h \
         rdp_cpu_ring.h rdp_cpu_ring_defs.h rdp_cpu_ring_inline.h \
         rdd_lookup_engine.h hwapi_mac.h unimac_drv.h; do
    fetch "$UBOOT/$f" "$OUT/uboot/$f"
done

echo ""
echo "=== Runner firmware (GPL uint32_t arrays) ==="
FW="release/src-rt-5.04axhnd.675x/rdp/projects/WL4908/firmware_bin"
for f in runner_fw_a.c runner_fw_b.c runner_fw_c.c runner_fw_d.c \
         predict_runner_fw_a.c predict_runner_fw_b.c \
         predict_runner_fw_c.c predict_runner_fw_d.c; do
    fetch "$FW/$f" "$OUT/firmware/$f"
done

echo ""
echo "=== Kernel RDP hardware drivers (BCM4908-specific) ==="
KRN="release/src-rt-5.02L.07p2axhnd/rdp/drivers/rdp_subsystem/BCM4908"
for f in data_path_init.c rdp_map.h rdp_drv_bbh.c rdp_drv_bpm.c \
         rdp_drv_sbpm.c rdp_drv_ih.c rdp_bbh_arrays.c \
         rdp_dma_arrays.c rdp_runner_arrays.c; do
    fetch "$KRN/$f" "$OUT/kernel-driver/$f"
done

echo ""
echo "=== Runner labels ==="
LBL="release/src-rt-5.02L.07p2axhnd/rdp/projects/WL4908/firmware_bin"
for f in rdd_runner_a_labels.h rdd_runner_b_labels.h \
         rdd_runner_c_labels.h rdd_runner_d_labels.h; do
    fetch "$LBL/$f" "$OUT/firmware/$f"
done

echo ""
echo "=== Done ==="
du -sh "$OUT"
echo "Files saved to $OUT"
