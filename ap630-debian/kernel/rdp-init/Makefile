KDIR ?= /tmp/ap630-debian/linux-6.12
CROSS_COMPILE ?= aarch64-linux-gnu-
ARCH ?= arm64

# Firmware source
FW_SRC ?= /tmp/asuswrt-rdp/release/src-rt-5.04axhnd.675x/rdp/projects/WL4908/firmware_bin

# Module objects
obj-m := rdp_power.o rdp_full_init.o

# rdp_full_init is a composite module built from multiple source files
rdp_full_init-y := rdp_init_mod.o
rdp_full_init-y += rdp_src/data_path_init.o
rdp_full_init-y += rdp_src/rdd_init.o
rdp_full_init-y += rdp_src/rdd_common.o
rdp_full_init-y += rdp_src/rdd_tm.o
rdp_full_init-y += rdp_src/rdd_cpu.o
rdp_full_init-y += rdp_src/rdp_drv_bbh.o
rdp_full_init-y += rdp_src/rdp_drv_bpm.o
rdp_full_init-y += rdp_src/rdp_drv_sbpm.o
rdp_full_init-y += rdp_src/rdp_drv_ih.o
rdp_full_init-y += rdp_src/rdp_bbh_arrays.o
rdp_full_init-y += rdp_src/rdp_dma_arrays.o
rdp_full_init-y += rdp_src/runner_fw_a.o
rdp_full_init-y += rdp_src/runner_fw_b.o
rdp_full_init-y += rdp_src/runner_fw_c.o
rdp_full_init-y += rdp_src/runner_fw_d.o
rdp_full_init-y += rdp_src/predict_runner_fw_a.o
rdp_full_init-y += rdp_src/predict_runner_fw_b.o
rdp_full_init-y += rdp_src/predict_runner_fw_c.o
rdp_full_init-y += rdp_src/predict_runner_fw_d.o

# Include paths
ccflags-y := -I$(src) -I$(src)/rdp_src -I$(FW_SRC)
# The shim must be included before anything else
ccflags-y += -include $(src)/uboot_shim.h
# Suppress warnings from vendor code (it's massive and we can't fix it all)
ccflags-y += -Wno-unused-variable -Wno-unused-function -Wno-sign-compare
ccflags-y += -Wno-pointer-to-int-cast -Wno-int-to-pointer-cast
ccflags-y += -Wno-format -Wno-missing-declarations

all:
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=$(ARCH) clean
	rm -rf rdp_src/*.o rdp_src/.*.cmd
