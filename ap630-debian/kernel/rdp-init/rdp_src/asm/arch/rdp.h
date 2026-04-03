/* Replacement for U-Boot's <asm/arch/rdp.h> — provides BCM4908 base addresses */
#ifndef _ASM_ARCH_RDP_H
#define _ASM_ARCH_RDP_H

/* Physical base addresses for BCM4908 RDP blocks.
 * These are used by rdp_map.h to compute block offsets.
 * DEVICE_ADDRESS() in access_macros.h masks these to 20-bit offsets
 * and adds soc_base_address (our ioremap'd virtual address). */
#define RDP_BASE		0x82200000
#define FPM_BPM_PHYS_BASE	0x82c30000
#define FPM_BPM_SIZE		0x134

#endif
