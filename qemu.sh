#!/bin/bash

#set -x
export PATH=/home/.local/bin:$PATH

HOMEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HVL_WORKSPACE=$HOMEDIR/hvlws

MY_NAME="$(basename $0)"
__SRCDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HVL_WORKSPACE=${HVL_WORKSPACE:-hvlws}
cd $HVL_WORKSPACE
export HVL_WORKSPACE_PATH=$(realpath .)
echo "Using workspace $HVL_WORKSPACE"

QEMU_XLNX_PATH=$HVL_WORKSPACE_PATH/qemu_inst/bin

echo 
echo 'FIRST WINDOW'
echo
echo "QEMU PMU"
echo "--------"
echo 'USE THIS'
echo 'rm /tmp/qemu-memory-_*'
echo
echo 'OLD COMMAND'
echo "$QEMU_XLNX_PATH/qemu-system-microblazeel -M microblaze-fdt -nographic \
-dtb $HVL_WORKSPACE_PATH/xilinx-zcu102-2020.2/pre-built/linux/images/zynqmp-qemu-multiarch-pmu.dtb \
-kernel $HVL_WORKSPACE_PATH/xilinx-zcu102-2020.2/pre-built/linux/images/pmu_rom_qemu_sha3.elf \
-device loader,file=$HVL_WORKSPACE_PATH/xilinx-zcu102-2020.2/pre-built/linux/images/pmufw.elf -machine-path /tmp
"
echo
echo 'USE THIS'
echo "$QEMU_XLNX_PATH/qemu-system-microblazeel -M microblaze-fdt -display none \
-hw-dtb $HVL_WORKSPACE_PATH/out/images/zynqmp-qemu-multiarch-pmu.dtb \
-kernel $HVL_WORKSPACE_PATH/out/images/pmu_rom_qemu_sha3.elf \
-device loader,file=$HVL_WORKSPACE_PATH/out/images/pmufw.elf \
-device loader,addr=0xfd1a0074,data=0x1011003,data-len=4 \
-device loader,addr=0xfd1a007C,data=0x1010f03,data-len=4 \
-machine-path /tmp
"
echo

#2
echo 'SECOND WINDOW'
echo
echo "PETALINUX (A53)"
echo "---------------"
echo 'OLD COMMAND'
echo "$QEMU_XLNX_PATH/qemu-system-aarch64 -M arm-generic-fdt \
-dtb $HVL_WORKSPACE_PATH/xilinx-zcu102-2020.2/pre-built/linux/images/zynqmp-qemu-multiarch-arm.dtb \
-device loader,file=$HVL_WORKSPACE_PATH/xilinx-zcu102-2020.2/pre-built/linux/images/bl31.elf,cpu-num=0 \
-global xlnx,zynqmp-boot.cpu-num=0 -global xlnx,zynqmp-boot.use-pmufw=true -machine-path /tmp -net nic -net nic -net nic -net nic \
-net user,tftp=$HVL_WORKSPACE_PATH/out/tftp,hostfwd=tcp::30022-:22 \
-serial mon:stdio -m 4G --nographic -serial telnet:localhost:4321,server,wait=off -echr 2 \
-drive file=$HVL_WORKSPACE_PATH/out/linux-sd.wic,if=sd,format=raw,index=1 \
-device loader,file=$HVL_WORKSPACE_PATH/xilinx-zcu102-2020.2/pre-built/linux/images/u-boot.elf
"
echo
echo 'USE THIS'
echo "$QEMU_XLNX_PATH/qemu-system-aarch64 -M arm-generic-fdt \
-hw-dtb $HVL_WORKSPACE_PATH/out/images/zynqmp-qemu-multiarch-arm.dtb \
-dtb $HVL_WORKSPACE_PATH/out/tftp/dtb.dtb \
-m 4G \
-device loader,file=$HVL_WORKSPACE_PATH/out/images/bl31.elf,cpu-num=0 \
-device loader,file=$HVL_WORKSPACE_PATH/out/images/u-boot.elf \
-global xlnx,zynqmp-boot.cpu-num=0 -global xlnx,zynqmp-boot.use-pmufw=true \
-serial mon:stdio \
-display none \
-net nic -net nic -net nic -net nic \
-net user,tftp=$HVL_WORKSPACE_PATH/out/tftp,hostfwd=tcp::30022-:22 \
-serial telnet:localhost:4321,server,wait=off -echr 2 \
-drive file=$HVL_WORKSPACE_PATH/out/sd/zcu102-linux.img,if=sd,format=raw,index=1 \
-machine-path /tmp \
-boot mode=5
"

echo "U-Boot configuration: "
echo 'OLD COMMAND'
echo '
setenv bootargs "earlycon clk_ignore_unused root=/dev/mmcblk0p2 ro rootwait earlyprintk debug uio_pdrv_genirq.of_id=generic-uio";
dhcp 200000 Image; dhcp 100000 dtb.dtb;
setenv initrd_high 78000000; booti 200000 - 100000;'
echo
echo 'USE THIS'
echo 'setenv bootargs "earlycon clk_ignore_unused root=/dev/mmcblk0p2 ro rootwait earlyprintk debug uio_pdrv_genirq.of_id=generic-uio";
setenv initrd_high 78000000; boot;
'
echo

#3
echo 'THIRD WINDOW'
echo
echo "Zephyr (R5)"
echo "-----------"
echo 'telnet localhost 4321'
echo

#4
echo 'FOURTH WINDOW'
echo
echo '
After booting, Linux on A53 can also be accessed as:
ssh -oHostKeyAlgorithms=+ssh-rsa root@127.0.0.1 -p 30022
'
echo 'echo start >/sys/class/remoteproc/remoteproc0/state'

#/home/dan/projects/cto/appstar/src/zynq_ipi/hvl/binaries/u-boot_d1.elf



exit 0
