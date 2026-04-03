# BCM4908 Runner Data Path (RDP) — Reverse Engineering Notes

## Goal

Enable line-rate GbE forwarding on the AP630 by initializing the Runner
hardware packet accelerator. The mainline `bcm4908_enet` driver's iuDMA path
is hardware-limited to ~10 Mbps RX. TX via iuDMA works at ~700 Mbps.

## Stock Firmware Analysis

Source: NAND backup of HiveOS IQ Engine 10.6r7 (mtd6, squashfs at offset 64).

### Module Load Order (from /opt/ah/etc/networkInit.sh)

```
1. rdp_fpm.ko     — Free Pool Manager (RDP buffer allocation)
2. bdmf.ko        — Broadcom Device Management Framework (object model)
3. rdpa_gpl.ko    — RDPA GPL layer (91 exported functions)
4. rdpa_gpl_ext.ko
5. bcmlibs.ko     — Shared libraries
6. rdpa.ko        — Main RDP API (2.1 MB, 1159 text symbols, 2449 total)
7. rdpa_mw.ko     — Middleware
8. rdpa_cmd.ko    — Command interface
9. chipinfo.ko
10. pktflow.ko    — Flow cache (275 KB)
11. bcm_enet.ko   — Vendor enet driver with RDP integration (274 KB)
12. cmdlist.ko    — Runner command lists (126 KB)
13. pktrunner.ko  — Flow acceleration engine (90 KB)
```

### Key Symbol Categories in rdpa.ko

| Category | Count | Purpose |
|----------|-------|---------|
| `rdd_*` | 296 | Runner Data Descriptor — programs the Runner processor |
| `fi_bl_drv_*` | 140 | Hardware abstraction (BBH, BPM, DMA, SBPM) |
| `BBH_*` (data) | ~80 | Broadband Handler register config arrays |
| `RUNNER_REGS_*` | ~30 | Runner processor register config arrays |
| `cpu_*` | ~20 | CPU port management (RX/TX to/from Runner) |
| `port_*` | ~15 | Port configuration |
| `system_*` | ~10 | System-level init |

### Runner Firmware (Embedded in rdpa.ko)

Four Runner processor cores, each with its own firmware:

| Symbol | Offset | Size | Purpose |
|--------|--------|------|---------|
| `firmware_binary_A` | 0x4ed30 | ~32 KB | Runner core A microcode |
| `firmware_binary_B` | 0x56d38 | ~32 KB | Runner core B microcode |
| `firmware_binary_C` | 0x5ed40 | ~32 KB | Runner core C microcode |
| `firmware_binary_D` | 0x66d48 | ~32 KB | Runner core D microcode |
| `firmware_predict_A-D` | 0x4cb70+ | ~1 KB each | Branch prediction tables |

The firmware is for the Runner's proprietary RISC cores (not ARM). These handle
packet classification, forwarding, and DMA at wire speed.

### Critical Init Functions

```
system_data_path_init
  -> runner_reserved_memory_get  (maps RDP reserved memory from DTS)
  -> fpm_get_hw_info             (Free Pool Manager hardware params)
  -> data_path_init
       -> init_rdp_virtual_mem   (virtual memory mapping)
       -> rdd_runner_frequency_set
       -> fpm_reset_bb           (reset buffer pool)
       -> fi_bl_drv_bpm_init     (init buffer pool manager)
       -> fi_bl_drv_bpm_set_user_group_thresholds
  -> rdd_ddr_headroom_size_config
  -> rdd_interrupt_mask          (x8, masks all Runner interrupts)
  -> rdd_wan_channel_set
  -> rdd_wan_channel_rate_limiter_config
  -> rdd_us_wan_flow_config
```

### Hardware Blocks

| Block | Purpose | Key Functions |
|-------|---------|---------------|
| **BBH RX** | Broadband Handler — receives from switch, feeds Runner | `fi_bl_drv_bbh_rx_set_configuration` |
| **BBH TX** | Broadband Handler — sends from Runner to switch/CPU | `fi_bl_drv_bbh_tx_set_configuration` |
| **BPM** | Buffer Pool Manager — allocates packet buffers | `fi_bl_drv_bpm_init` |
| **FPM** | Free Pool Manager — token-based buffer management | `fpm_alloc_buffer`, `fpm_free_buffer` |
| **SBPM** | Status Buffer Pool Manager | `fi_bl_drv_sbpm_*` |
| **DMA** | Runner's DMA engine (separate from iuDMA) | `fi_bl_drv_dma_*` |
| **Runner Cores** | 4 RISC processors for packet processing | Firmware binaries A-D |

### Reserved Memory (from DTS)

```
rdp1@6000000: 32 MB at 96 MB  — Runner DMA region 1
rdp2@3400000: 44 MB at 52 MB  — Runner DMA region 2
```

These regions are used by the Runner for packet buffers and descriptor rings.
They must NOT overlap with Linux kernel memory.

## Next Steps for RE

1. **Extract firmware binaries** from rdpa.ko data section for offline analysis
2. **Check asuswrt-merlin.ng GPL source** — **CHECKED (2026-04-03)**
   The situation is layered — RDPA/BDMF are binary blobs, but the hardware
   drivers beneath them are **full GPL source**:
   - `rdp/drivers/rdp_subsystem/BCM4908/data_path_init.c` — full init sequence
   - `rdp/drivers/rdp_subsystem/BCM4908/rdp_drv_bbh.c` (362 KB) — BBH RX/TX config
   - `rdp/drivers/rdp_subsystem/BCM4908/rdp_drv_bpm.c` — BPM init, full source
   - `rdp/drivers/rdp_subsystem/BCM4908/rdp_drv_sbpm.c` — SBPM init
   - `rdp/drivers/rdp_subsystem/BCM4908/rdp_drv_ih.c` — Ingress Handler
   - `rdp_bbh_arrays.c`, `rdp_dma_arrays.c`, `rdp_runner_arrays.c` — HW config tables
   - Full register headers: `rdp_bbh.h`, `rdp_bpm.h`, `rdp_dma.h`, `rdp_map.h`, etc.
   - RDD layer: `rdp/projects/DSL_63138/drivers/rdd/rdd_init.c` (143 KB), 30+ files
     with WL4908-specific `#ifdef` paths
   - Runner firmware: `runner_fw_a.c`–`runner_fw_d.c` as loadable `uint32_t` C arrays
   Binary-only: BDMF (`bdmf.o`), RDPA core (`rdpa.o`).
   **Strategy:** bypass BDMF/RDPA, write a minimal kernel module using the
   register-level drivers to init BBH+BPM+DMA and load Runner firmware directly.
3. **Boot stock HiveOS and dump Runner register state** while traffic flows
   - Use root shell (CVE-2025-27229) to read MMIO registers
   - Compare with config arrays in GPL source
4. **Focus on minimal viable path**: just configure BBH + BPM + DMA for
   CPU-to-switch forwarding, skip flow cache and WiFi offload
   - `data_path_init.c` has the exact init sequence
   - Runner firmware C arrays can be loaded directly onto the Runner cores
   - No need for BDMF/RDPA if we only need basic forwarding
5. **Alternative**: try loading the stock rdpa.ko stack on our kernel
   - Would need kernel 4.1.52 ABI compatibility or symbol shimming
   - Stock modules are for aarch64 Linux 4.1.52 SMP PREEMPT

## iuDMA Tuning Results (2026-04-03)

Confirmed that the ~10 Mbps limit is a **hardware property** of the iuDMA engine,
not a software or configuration issue. Tested via live register writes on running system:

- OK_TO_SEND (0x80002040): 7→15, no throughput change
- DMA burst length (0x80002a0c): 8→16, no change; 32 crashes DMA
- Flow control enable (0x80002800 bit 1): breaks networking
- All switch ports and UMAC confirmed at 1000 Mbps
- Overflow counter stays 0 — no drops at the ENET block level
- ~844 IRQs/sec during load (~1 packet per interrupt, no NAPI batching benefit)
- Throughput is byte-rate limited (scales 5→9.5 Mbps from 64→1400 byte packets)
- The "700 Mbps UDP TX" was sender-side only; receiver gets 9.4 Mbps with 99% loss
