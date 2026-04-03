KDIR ?= /tmp/ap630-debian/linux-6.12
CROSS_COMPILE ?= aarch64-linux-gnu-
ARCH ?= arm64

obj-m := rdp_power.o

all:
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=$(ARCH) clean
