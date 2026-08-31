obj-m += r8q-camprobe.o

KDIR ?= /home/sitsirk/r8q-linux/kernel-work/out

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=arm64 LLVM=1 modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) ARCH=arm64 LLVM=1 clean
