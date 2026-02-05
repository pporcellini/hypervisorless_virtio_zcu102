#!/bin/bash

set -x

ip tuntap del mode tap tap0;ip tuntap add mode tap user $USER tap0;ifconfig tap0 192.168.200.254 up
#insmod /lib/modules/5.4.0-xilinx-v2020.2-dirty/kernel/drivers/remoteproc/zynqmp_r5_remoteproc.ko
#cd /hvl/
insmod user-mbox.ko
cp /hvl/zephyr.elf /lib/firmware/
insmod /lib/modules/5.4.0-xilinx-v2020.2-dirty/kernel/drivers/remoteproc/zynqmp_r5_remoteproc.ko
echo zephyr.elf >/sys/class/remoteproc/remoteproc0/firmware

/hvl/lkvm run --debug --vxworks --rsld --pmm --debug-nohostfs --transport mmio --shmem-addr 0x37000000 --shmem-size 0x1000000 --cpus 1 --mem 128 --no-dtb --debug --rng --network mode=tap,tapif=tap0,trans=mmio --vproxy
