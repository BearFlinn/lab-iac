// SPDX-License-Identifier: GPL-2.0
/*
 * BCM4908 Runner Data Path init kernel module.
 *
 * Compiles the asuswrt-merlin U-Boot RDP init code as a kernel module
 * using a thin shim layer. On insmod, initializes the Runner hardware
 * blocks (BBH, BPM, SBPM, IH, DMA) and loads firmware onto the Runner
 * cores, enabling hardware packet acceleration.
 *
 * Prerequisites:
 *   - rdp_power.ko loaded (powers on RDP and FPM via PMB)
 *   - Kernel built with BCM4908 support
 *
 * The init sequence follows data_path_init() from:
 *   asuswrt-merlin.ng/release/src-rt-5.04axhnd.675x/bootloaders/
 *   u-boot-2019.07/arch/arm/mach-bcmbca/rdp/data_path_init.c
 */

#include <linux/module.h>
#include <linux/io.h>
#include <linux/dma-mapping.h>
#include "data_path_init.h"

/* RDP physical addresses */
#define RDP_PHYS_BASE	0x82200000
#define RDP_SIZE	0x100000
#define FPM_PHYS_BASE	0x82c00000
#define FPM_SIZE	0x80000

/* Reserved memory for RDP DMA (from DTS) */
#define RDP_DDR1_PHYS	0x06000000	/* 32 MB at 96 MB */
#define RDP_DDR1_SIZE	0x02000000
#define RDP_DDR2_PHYS	0x03400000	/* 44 MB at 52 MB */
#define RDP_DDR2_SIZE	0x02c00000

/* The global RDP virtual base — used by DEVICE_ADDRESS() in the shim */
void __iomem *rdp_virt_base;
EXPORT_SYMBOL(rdp_virt_base);

/* soc_base_address — used by access_macros.h DEVICE_ADDRESS() macro.
 * Points to the ioremap'd RDP base. */
uint8_t *soc_base_address;

static void __iomem *fpm_virt_base;

/* BPM virtual base (used by the BPM driver functions) */
void __iomem *g_bpm_virt_base;

/* Connection table pointer — used by rdd_data_structures.h */
void *g_ds_connection_table_ptr;

static int __init rdp_init_module(void)
{
	pr_info("rdp_init: mapping RDP at 0x%x (%d KB)\n", RDP_PHYS_BASE, RDP_SIZE / 1024);

	rdp_virt_base = ioremap(RDP_PHYS_BASE, RDP_SIZE);
	soc_base_address = (uint8_t *)rdp_virt_base;
	if (!rdp_virt_base) {
		pr_err("rdp_init: failed to ioremap RDP\n");
		return -ENOMEM;
	}

	fpm_virt_base = ioremap(FPM_PHYS_BASE, FPM_SIZE);
	if (!fpm_virt_base) {
		pr_err("rdp_init: failed to ioremap FPM\n");
		iounmap(rdp_virt_base);
		return -ENOMEM;
	}

	/* Verify RDP is accessible */
	{
		u32 val = readl(rdp_virt_base + 0x99000);
		pr_info("rdp_init: Runner0 GLOBAL_CTRL = 0x%08x\n", val);
	}

	/* Verify FPM is accessible */
	{
		u32 val = readl(fpm_virt_base);
		pr_info("rdp_init: FPM[0] = 0x%08x\n", val);
	}

	/* Configure the RDP init parameters.
	 * DDR buffer memory uses the reserved rdp1 region (32 MB at 96 MB).
	 * DDR flow manager uses the reserved rdp2 region (44 MB at 52 MB).
	 * These are marked no-map in the DTS so Linux doesn't touch them. */
	{
		/* The U-Boot RDP code uses uint32_t for virtual addresses (32-bit).
		 * On ARM64, we can't fit kernel virtual addresses in 32 bits.
		 *
		 * WORKAROUND: The BCM4908 has only 1 GB RAM, so physical addresses
		 * are < 0x40000000. Use memremap to map the reserved DDR regions
		 * and pass the PHYSICAL addresses in the virtual address fields.
		 * The init code will write these physical addresses to Runner SRAM
		 * for hardware DMA. For CPU-side struct initialization, the code
		 * uses MWRITE_32 macros which we override to handle this.
		 *
		 * The key insight: the init code mostly writes phys addresses TO
		 * Runner SRAM (MMIO). The only CPU-side DDR accesses are memset/
		 * memcpy during structure init, which we can skip for now (the
		 * reserved regions retain U-Boot's initialized state). */
		void *ddr_tm = memremap(RDP_DDR1_PHYS, RDP_DDR1_SIZE, MEMREMAP_WB);
		void *ddr_mc = memremap(RDP_DDR2_PHYS, RDP_DDR2_SIZE, MEMREMAP_WB);
		S_DPI_CFG dpi_cfg;

		if (!ddr_tm || !ddr_mc) {
			pr_err("rdp_init: failed to memremap DDR\n");
			if (ddr_tm) memunmap(ddr_tm);
			if (ddr_mc) memunmap(ddr_mc);
			iounmap(fpm_virt_base);
			iounmap(rdp_virt_base);
			return -ENOMEM;
		}
		pr_info("rdp_init: DDR tm=%px (phys 0x%x) mc=%px (phys 0x%x)\n",
			ddr_tm, RDP_DDR1_PHYS, ddr_mc, RDP_DDR2_PHYS);

		memset(&dpi_cfg, 0, sizeof(dpi_cfg));
		dpi_cfg.mtu_size = 1536;
		dpi_cfg.headroom_size = 0;
		dpi_cfg.runner_freq = 0;
		dpi_cfg.runner_tm_base_addr = (uintptr_t)ddr_tm;
		dpi_cfg.runner_tm_base_addr_phys = RDP_DDR1_PHYS;
		dpi_cfg.runner_tm_size = RDP_DDR1_SIZE >> 20;
		dpi_cfg.runner_mc_base_addr = (uintptr_t)ddr_mc;
		dpi_cfg.runner_mc_base_addr_phys = RDP_DDR2_PHYS;
		dpi_cfg.runner_mc_size = RDP_DDR2_SIZE >> 20;
		dpi_cfg.runner_lp = 0;
		uint32_t rc;

		pr_info("rdp_init: calling data_path_init()...\n");
		rc = data_path_init(&dpi_cfg);
		if (rc != DPI_RC_OK) {
			pr_err("rdp_init: data_path_init() FAILED: %u\n", rc);
			iounmap(fpm_virt_base);
			iounmap(rdp_virt_base);
			return -EIO;
		}
		pr_info("rdp_init: data_path_init() OK\n");

		pr_info("rdp_init: calling data_path_go()...\n");
		rc = data_path_go();
		if (rc != DPI_RC_OK) {
			pr_err("rdp_init: data_path_go() FAILED: %u\n", rc);
		} else {
			pr_info("rdp_init: data_path_go() OK — Runner enabled!\n");
		}

		/* Check Runner state after init */
		{
			u32 ctrl0 = readl(rdp_virt_base + 0x99000);
			u32 ctrl1 = readl(rdp_virt_base + 0x9a000);
			pr_info("rdp_init: Runner0 CTRL=0x%08x Runner1 CTRL=0x%08x\n",
				ctrl0, ctrl1);
		}
	}
	return 0;
}

static void __exit rdp_exit_module(void)
{
	/* TODO: disable Runner cores, clean up */
	if (fpm_virt_base)
		iounmap(fpm_virt_base);
	if (rdp_virt_base)
		iounmap(rdp_virt_base);
	pr_info("rdp_init: unloaded\n");
}

module_init(rdp_init_module);
module_exit(rdp_exit_module);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("BCM4908 Runner Data Path initialization");
