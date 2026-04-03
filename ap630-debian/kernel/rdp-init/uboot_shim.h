/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Shim to compile asuswrt-merlin U-Boot RDP source as a Linux kernel module.
 * Provides kernel equivalents for U-Boot functions and types.
 *
 * IMPORTANT: This header is force-included before all source files via
 * -include uboot_shim.h. It must NOT conflict with the U-Boot RDP headers
 * (access_macros.h, packing.h, etc.) which define their own MMIO macros.
 */
#ifndef _UBOOT_SHIM_H_
#define _UBOOT_SHIM_H_

#ifdef __KERNEL__

#include <linux/kernel.h>
#include <linux/string.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/types.h>

/* U-Boot compat — function replacements */
#define printf		pr_info
#define malloc(sz)	kmalloc(sz, GFP_KERNEL)
#define free		kfree

/* Prevent U-Boot's <common.h> from being included */
#define __UBOOT__
/* But undefine it if a source file checks for it to use U-Boot-specific paths */
/* Actually, some code uses #ifdef __UBOOT__ for U-Boot-specific paths that we want */

/* Endianness — BCM4908 is little-endian ARM64 */
#define _BYTE_ORDER_LITTLE_ENDIAN_

/* Not in simulation mode */
#undef BDMF_SYSTEM_SIM

/* Target platform — selects WL4908-specific constants in auto headers */
#define WL4908

/* Not in firmware init mode */
#undef FIRMWARE_INIT

/* The U-Boot RDP code uses soc_base_address as the ioremap'd RDP base.
 * access_macros.h references this as an extern. We provide it from rdp_init_mod.c. */

/* Suppress warnings from the large auto-generated vendor headers */
#pragma GCC diagnostic ignored "-Wunused-variable"
#pragma GCC diagnostic ignored "-Wunused-function"

/* Kernel's FIELD_GET macro conflicts with the vendor's version.
 * Prevent the kernel's bitfield.h from being included by vendor code. */
#define __LINUX_BITFIELD_H

/* Packing attributes — the vendor headers use these */
#ifndef __PACKING_ATTRIBUTE_STRUCT_END__
#define __PACKING_ATTRIBUTE_STRUCT_END__	__attribute__((packed))
#endif
#ifndef __PACKING_ATTRIBUTE_FIELD_LEVEL__
#define __PACKING_ATTRIBUTE_FIELD_LEVEL__
#endif

/* SOC_BASE_ADDRESS macro used by some code paths in access_macros.h */
#define USE_SOC_BASE_ADDR

/* rdp_mm memory operations are defined in rdp_mm.h from the vendor source.
 * We provide noncached_alloc/noncached_free stubs since we don't need
 * U-Boot's non-cached memory allocator. */
static inline void *noncached_alloc(size_t sz, unsigned long align) { return kmalloc(sz, GFP_KERNEL); }
static inline void noncached_free(size_t sz, void *p) { kfree(p); }
static inline void *memalign(size_t align, size_t sz) { return kmalloc(sz, GFP_KERNEL); }

/* Broadcom's bdmf types — let bdmf_data_types.h handle these */
/* typedef char bdmf_boolean — defined in bdmf_data_types.h */
/* typedef int bdmf_error — defined in bdmf_errno.h */
#define bdmf_ioremap(phys, sz) ioremap(phys, sz)
#define bdmf_iounmap(virt)     iounmap(virt)

/* RDD virtual-to-physical address translation for reserved memory */
#define RDD_RSV_VIRT_TO_PHYS(vbase, pbase, vaddr) \
	((uint32_t)(uintptr_t)(pbase) + ((uint32_t)(uintptr_t)(vaddr) - (uint32_t)(uintptr_t)(vbase)))

/* Round up to 1 MB boundary */
#define ROUND_UP_MB(addr) (((uintptr_t)(addr) + 0xFFFFF) & ~0xFFFFF)

/* Forward declarations removed — rdd_rdd_emac now comes from auto headers with WL4908 defined */

/* Constants missing from this firmware build's auto headers.
 * These are thread numbers and addresses specific to the WL4908 firmware.
 * Values extracted from the kernel driver's auto headers (5.02L tree). */
#ifndef GPON_RX_NORMAL_DESCRIPTORS_ADDRESS
#define GPON_RX_NORMAL_DESCRIPTORS_ADDRESS  0xb000  /* WAN RX normal queue */
#endif
#ifndef GPON_RX_DIRECT_DESCRIPTORS_ADDRESS
/* already defined in some versions */
#endif
#ifndef LAN1_FILTERS_AND_CLASSIFICATION_THREAD_NUMBER
#define LAN1_FILTERS_AND_CLASSIFICATION_THREAD_NUMBER 16
#endif
#ifndef WAN_DIRECT_THREAD_NUMBER
#define WAN_DIRECT_THREAD_NUMBER 7
#endif
#ifndef ETHWAN_ABSOLUTE_TX_BBH_COUNTER_ADDRESS
#define ETHWAN_ABSOLUTE_TX_BBH_COUNTER_ADDRESS 0xb2c0
#endif
#ifndef EMAC_ABSOLUTE_TX_BBH_COUNTER_ADDRESS
/* Same as the one without ETHWAN prefix in this version */
#endif
#ifndef MAC_TABLE_CAM_ADDRESS
#define MAC_TABLE_CAM_ADDRESS 0x3e00
#endif
#ifndef MAC_CONTEXT_TABLE_ADDRESS
#define MAC_CONTEXT_TABLE_ADDRESS 0x4000
#endif
#ifndef MAC_CONTEXT_TABLE_CAM_ADDRESS
#define MAC_CONTEXT_TABLE_CAM_ADDRESS 0x4200
#endif
#ifndef SBPM_REPLY_ADDRESS
/* Should be defined in auto header */
#endif
/* RDD_CONTEXT_TABLE_DTS now comes from auto headers with WL4908 */

#else
#error "This shim is for kernel module compilation only"
#endif
#endif /* _UBOOT_SHIM_H_ */
