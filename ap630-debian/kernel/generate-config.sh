#!/bin/bash
# Generate the AP630 kernel config from arm64 defconfig.
# Run from the root of a Linux 6.12.x kernel source tree.
#
# Target: Image under 16 MB uncompressed (Broadcom U-Boot CONFIG_SYS_BOOTM_LEN limit).

set -euo pipefail

ARCH=arm64
CROSS=aarch64-linux-gnu-

make ARCH=$ARCH CROSS_COMPILE=$CROSS defconfig > /dev/null 2>&1

scripts/config --enable CONFIG_CC_OPTIMIZE_FOR_SIZE

# Strip unnecessary ARM64 platforms
for arch in ACTIONS APPLE EXYNOS FPE HISI K3 LAYERSCAPE LG MEDIATEK MESON \
            MVEBU MXC NPCM QCOM REALTEK RENESAS ROCKCHIP S32 SPARX5 SPRD \
            SUNXI TEGRA TESLA_FSD TI_K3 THUNDER THUNDER2 UNIPHIER VEXPRESS \
            VIRT VISCONTI XGENE ZTE AIROHA ALPINE BCM2835 BCM_IPROC BRCMSTB \
            BERLIN LG1K KEEMBAY NXP MA35 SEATTLE INTEL_SOCFPGA STM32 \
            SYNQUACER ZYNQMP; do
    scripts/config --disable CONFIG_ARCH_$arch 2>/dev/null || true
done

# Strip large unnecessary subsystems (headless ARM router)
# SERIAL_8250 conflicts with bcm63xx_uart — both register "ttyS" namespace.
# 8250 runs first (arch_initcall), bcm63xx_uart gets -EBUSY. BCM4908 has no 8250 UARTs.
for opt in SERIAL_8250 SERIAL_8250_CONSOLE SERIAL_AMBA_PL011 SERIAL_AMBA_PL011_CONSOLE \
           DRM FB SOUND SND WIRELESS WLAN BT NFC CAN MEDIA_SUPPORT STAGING \
           XFS_FS BTRFS_FS KVM VIRTUALIZATION SECURITY_SELINUX SECURITY_APPARMOR \
           ACPI EFI HUGETLB_PAGE TRANSPARENT_HUGEPAGE NUMA MEMORY_HOTPLUG \
           INPUT HID SUSPEND HIBERNATION FTRACE KPROBES PROFILING \
           DEBUG_INFO DEBUG_INFO_DWARF5 DEBUG_INFO_BTF AUDIT \
           BPF_SYSCALL CGROUP_BPF CGROUP_PERF CGROUP_RDMA CGROUP_MISC \
           CGROUP_CPUACCT CGROUP_DEVICE CGROUP_FREEZER MEMCG \
           DM_CRYPT IP_NF_IPTABLES CRYPTO_USER PCI; do
    scripts/config --disable CONFIG_$opt 2>/dev/null || true
done

# Non-boot drivers as modules (size reduction)
for opt in BCM4908_ENET BCMGENET USB_STORAGE USB_XHCI_HCD USB_EHCI_HCD \
           USB_OHCI_HCD MTD_NAND_BRCMNAND NFTABLES NF_TABLES NF_NAT \
           NF_CONNTRACK VLAN_8021Q NET_DSA PCIE_BRCMSTB; do
    scripts/config --module CONFIG_$opt 2>/dev/null || true
done

# Boot-critical: must be built-in
# PCI omitted: no PCIe bus nodes in AP630 DTB, saves ~200K+ (46 options).
# PCIE_BRCMSTB is already a module — re-enable PCI later if USB3/XHCI needs it.
for opt in NET REGULATOR HWMON ARCH_BCMBCA ARCH_BCM BCM_PMB \
           PINCTRL_BCM4908 CLK_BCM_63XX SERIAL_BCM63XX SERIAL_BCM63XX_CONSOLE \
           BLK_DEV_INITRD TMPFS DEVTMPFS DEVTMPFS_MOUNT PROC_FS SYSFS \
           ARM_GIC ARM_ARCH_TIMER SMP TTY UNIX PRINTK; do
    scripts/config --enable CONFIG_$opt 2>/dev/null || true
done

# Resolve dependencies
make ARCH=$ARCH CROSS_COMPILE=$CROSS olddefconfig > /dev/null 2>&1

# Summary — only the essential info
BUILTINS=$(grep -c '=y$' .config)
MODULES=$(grep -c '=m$' .config)
echo "Config: ${BUILTINS} built-in, ${MODULES} modules"

# Verify critical options
MISSING=""
for opt in ARCH_BCMBCA SERIAL_BCM63XX_CONSOLE NET BLK_DEV_INITRD DEVTMPFS TTY; do
    if ! grep -q "CONFIG_${opt}=y" .config; then
        MISSING="$MISSING $opt"
    fi
done
if [[ -n "$MISSING" ]]; then
    echo "WARNING: missing critical options:$MISSING"
    exit 1
fi
echo "Critical options verified OK"
