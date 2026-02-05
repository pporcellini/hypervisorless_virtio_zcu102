#!/bin/bash

set -x
#export PATH=/home/.local/bin:$PATH

HOMEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HVL_WORKSPACE=$HOMEDIR/hvlws

XLNX_COMMON_PACKAGE=${XLNX_COMMON_PACKAGE:-$HOMEDIR/dl/xilinx-zynqmp-common-v2020.2.tar.gz}
XLNX_ZCU102_BSP=${XLNX_ZCU102_BSP:-$HOMEDIR/dl/xilinx-zcu102-v2020.2-final.bsp}

BUILD_PETALINUX=1
BUILD_QEMU_XILINX=1
BUILD_LINUX=1
BUILD_DTB=1
BUILD_KVM_MODS=1
BUILD_ZEPHYR=1
BUILD_SD=1

function check_status { if [ $1 != 0 ]; then echo "Error ${1} @ [${MY_NAME}:${2}]. EXIT" ; exit ${1};fi }

MY_NAME="$(basename $0)"
__SRCDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

HVL_WORKSPACE=${HVL_WORKSPACE:-hvlws}
mkdir -p $HVL_WORKSPACE
cd $HVL_WORKSPACE
check_status $? $LINENO
export HVL_WORKSPACE_PATH=$(realpath .)

echo "Using workspace $HVL_WORKSPACE"

mkdir -p $HVL_WORKSPACE_PATH/out/tftp
mkdir -p $HVL_WORKSPACE_PATH/sysroot
mkdir -p $HVL_WORKSPACE_PATH/out/target/hvl

if [ ! -f $XLNX_COMMON_PACKAGE ]; then
	echo "Download ZYNQMP common image v2020.2 from https://www.xilinx.com/member/forms/download/xef.html?filename=xilinx-zynqmp-common-v2020.2.tar.gz and update XLNX_COMMON_PACKAGE in $__SRCDIR/$MY_NAME"
	exit 1
fi

if [ ! -f $XLNX_ZCU102_BSP ]; then
	echo "Download ZCU102 BSP v2020.2 from https://www.xilinx.com/member/forms/download/xef.html?filename=xilinx-zcu102-v2020.2-final.bsp and update XLNX_ZCU102_BSP in $__SRCDIR/$MY_NAME"
	exit 1
fi

if [ $BUILD_PETALINUX -eq 1 ]; then
	tar xzf $XLNX_COMMON_PACKAGE
	check_status $? $LINENO

	cp $XLNX_ZCU102_BSP $(basename $XLNX_ZCU102_BSP).tar.gz
	tar xzf $(basename $XLNX_ZCU102_BSP).tar.gz
	check_status $? $LINENO
	rm $(basename $XLNX_ZCU102_BSP).tar.gz

	cd $HVL_WORKSPACE_PATH/xilinx-zynqmp-common-v2020.2
	(echo $HVL_WORKSPACE_PATH/petalinux/2020.2; echo Y) | ./sdk.sh
	echo $PATH
fi

if [ $BUILD_QEMU_XILINX -eq 1 ]; then
	#qemu xilinx
	echo "Building QEMU"
	cd $HVL_WORKSPACE
	rm -rf qemu
	
	#git clone https://github.com/Xilinx/qemu.git -b xilinx-v2021.1
	git clone https://github.com/Xilinx/qemu.git -b xlnx_rel_v2024.1
	check_status $? $LINENO
	cd qemu
	git submodule init
	git submodule update --recursive
	cd $HVL_WORKSPACE
	
	#workaround for sphinx-build version mismatch between zephyr and qemu zilinx
	if [ -f $HOME/.local/bin/sphinx-build ]; then
		mv $HOME/.local/bin/sphinx-build $HOME/.local/bin/sphinx-build_tmp_bk
	fi
	
	rm -rf qemu_build
	rm -rf qemu_inst
	mkdir qemu_build
	cd qemu_build
	../qemu/configure --target-list="aarch64-softmmu,microblazeel-softmmu,arm-softmmu" \
	--enable-debug --enable-fdt --disable-kvm \
	--disable-vnc \
	--prefix=$HVL_WORKSPACE_PATH/qemu_inst
	#--enable-gcrypt \
	check_status $? $LINENO

	#make -j$(nproc)
	make install -j$(nproc)
	check_status $? $LINENO

	#workaround for sphinx-build version mismatch between zephyr and qemu xilinx
	if [ ! -f $HOME/.local/bin/sphinx-build ]; then
		if [ -f $HOME/.local/bin/sphinx-build_tmp_bk ]; then
			mv $HOME/.local/bin/sphinx-build_tmp_bk $HOME/.local/bin/sphinx-build
		fi
	fi
#else
#	QEMU_XLNX_PATH=$HVL_WORKSPACE_PATH/zephyr-sdk-0.15.1/sysroots/x86_64-pokysdk-linux/usr/xilinx/bin
fi

QEMU_XLNX_PATH=$HVL_WORKSPACE_PATH/qemu_inst/bin
	
cd $HVL_WORKSPACE
source $HVL_WORKSPACE_PATH/petalinux/2020.2/environment-setup-aarch64-xilinx-linux
which aarch64-xilinx-linux-gcc
	
if [ $BUILD_LINUX -eq 1 ]; then

	#kernel xlnx
	git clone https://github.com/Xilinx/linux-xlnx.git -b xilinx-v2020.2
	cd linux-xlnx
	#git clone https://github.com/OpenAMP/linux-openamp-staging.git -b v2022.12
	#cd linux-openamp-staging
	check_status $? $LINENO

	cp $__SRCDIR/util/config_hvl .config
	CROSS_COMPILE=aarch64-xilinx-linux- ARCH=arm64 make olddefconfig
	check_status $? $LINENO
	sed -i 's%YYLTYPE yylloc%extern YYLTYPE yylloc%' scripts/dtc/dtc-lexer.l

	CROSS_COMPILE=aarch64-xilinx-linux- ARCH=arm64 make -j$(nproc)
	check_status $? $LINENO

	CROSS_COMPILE=aarch64-xilinx-linux- ARCH=arm64 make modules_install INSTALL_MOD_PATH=$HVL_WORKSPACE_PATH/mod_install/ -j$(nproc)
	check_status $? $LINENO

	cp $HVL_WORKSPACE_PATH/linux-xlnx/arch/arm64/boot/Image $HVL_WORKSPACE/out/tftp/
	#cp $HVL_WORKSPACE_PATH/linux-openamp-staging/arch/arm64/boot/Image $HVL_WORKSPACE/out/tftp/
fi

source $HVL_WORKSPACE_PATH/petalinux/2020.2/environment-setup-aarch64-xilinx-linux
cd $HVL_WORKSPACE_PATH
echo $PATH

if [ $BUILD_DTB -eq 1 ]; then
	#ZCU102 DTB
	#system-user.dtsi
	cp $__SRCDIR/util/system-user.dtsi $HVL_WORKSPACE_PATH/xilinx-zcu102-2020.2/components/plnx_workspace/device-tree/device-tree/
	check_status $? $LINENO

	cd $HVL_WORKSPACE_PATH/xilinx-zcu102-2020.2/components/plnx_workspace/device-tree/device-tree/
	check_status $? $LINENO
	gcc -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp system-top.dts -o dts.dts
	dtc -I dts -O dtb dts.dts -o dtb.dtb
	cp dtb.dtb $HVL_WORKSPACE_PATH/out/tftp
	echo $PATH
fi
if [ $BUILD_KVM_MODS -eq 1 ]; then
	cd $HVL_WORKSPACE_PATH

	#kvmtool
	git clone https://github.com/dgibson/dtc.git
	cd dtc
	CROSS_COMPILE=aarch64-xilinx-linux- ARCH=arm64 make WARNINGS=-Wno-error NO_PYTHON=1 install PREFIX=$HVL_WORKSPACE_PATH/sysroot
	check_status $? $LINENO

	cd $HVL_WORKSPACE_PATH

	git clone https://github.com/OpenAMP/openamp-kvmtool-staging.git -b hvl-integration kvmtool
	check_status $? $LINENO
	cd kvmtool
	CROSS_COMPILE=aarch64-xilinx-linux- ARCH=arm64 HVL_WORKSPACE=$HVL_WORKSPACE_PATH make -j8
	check_status $? $LINENO

	cd user-mbox-rsld
	make KDIR=$HVL_WORKSPACE_PATH/linux-xlnx
	#make KDIR=$HVL_WORKSPACE_PATH/linux-openamp-staging
	check_status $? $LINENO

	cp $__SRCDIR/util/chr_setup.sh $HVL_WORKSPACE_PATH/out/target
	check_status $? $LINENO

	cp $__SRCDIR/util/start.sh $HVL_WORKSPACE_PATH/out/target/hvl/
	check_status $? $LINENO
	
	cp $HVL_WORKSPACE_PATH/kvmtool/lkvm $HVL_WORKSPACE_PATH/out/target/hvl/
	check_status $? $LINENO

	cp $HVL_WORKSPACE_PATH/kvmtool/user-mbox-rsld/user-mbox.ko $HVL_WORKSPACE_PATH/out/target/hvl/
	check_status $? $LINENO

	cp -a $HVL_WORKSPACE_PATH/sysroot/lib/ $HVL_WORKSPACE_PATH/out/target/
	check_status $? $LINENO
	
	cp -a $HVL_WORKSPACE_PATH/mod_install/lib $HVL_WORKSPACE_PATH/out/target/
	echo $PATH
fi

if [ $BUILD_ZEPHYR -eq 1 ]; then
#zephyr

	cd $HVL_WORKSPACE_PATH
	wget --no-check-certificate -c https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.15.1/zephyr-sdk-0.15.1_linux-x86_64.tar.gz
	check_status $? $LINENO
	tar xzf zephyr-sdk-0.15.1_linux-x86_64.tar.gz
	cd $HVL_WORKSPACE_PATH/zephyr-sdk-0.15.1
	#wget --no-check-certificate -c https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.17.0/zephyr-sdk-0.17.0_linux-x86_64.tar.xz
	#tar xJf zephyr-sdk-0.17.0_linux-x86_64.tar.xz
	#cd $HVL_WORKSPACE_PATH/zephyr-sdk-0.17.0
	./setup.sh -t all -h -c



	cd $HVL_WORKSPACE_PATH
	source $HVL_WORKSPACE_PATH/zephyrenv/.venv/bin/activate 
	cd $HVL_WORKSPACE_PATH/zephyrenv
	export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
	export ZEPHYR_SDK_INSTALL_DIR=$HVL_WORKSPACE_PATH/zephyr-sdk-0.15.1
	#export ZEPHYR_SDK_INSTALL_DIR=$HVL_WORKSPACE_PATH/zephyr-sdk-0.17.0
	
	west init -m https://github.com/pporcellini/zephyr.git --mr demo-2022-12 zephyrproject
	#west init -m https://github.com/pporcellini/zephyr.git --mr prova1 zephyrproject
	#west init -m https://github.com/OpenAMP/openamp-system-reference.git --mf west-virtio-exp.yml zephyrproject
	cd zephyrproject
	west update
	west zephyr-export
	pip install -r zephyr/scripts/requirements.txt

	cd $HVL_WORKSPACE_PATH/zephyrenv/zephyrproject

	#filter petalinux host tools from PATH 
	export PATH=$(echo $PATH | tr ':' '\n'|grep -v 'petalinux/2020'|tr '\n' ':')

	west -v build -p auto -b qemu_cortex_r5 zephyr/samples/virtio/hvl_net_rng_reloc -- -DCMAKE_POLICY_VERSION_MINIMUM=3.5
	deactivate
	cp $HVL_WORKSPACE_PATH/zephyrenv/zephyrproject/build/zephyr/zephyr.elf $HVL_WORKSPACE_PATH/out/target/hvl/
fi

cd $HVL_WORKSPACE_PATH
#mkdir -p $HVL_WORKSPACE_PATH/mnt

#sdcard
#cp $HVL_WORKSPACE_PATH/xilinx-zcu102-2020.2/pre-built/linux/images/petalinux-sdimage.wic $HVL_WORKSPACE_PATH/linux-sd.wic
#$QEMU_XLNX_PATH/qemu-img resize $HVL_WORKSPACE_PATH/linux-sd.wic 8G
if [ $BUILD_LINUX -eq 1 ]; then
cp $HVL_WORKSPACE_PATH/xilinx-zcu102-2020.2/pre-built/linux/images/petalinux-sdimage.wic $HVL_WORKSPACE_PATH/out/linux-sd.wic
$QEMU_XLNX_PATH/qemu-img resize $HVL_WORKSPACE_PATH/out/linux-sd.wic 8G
fi
#parted resizepart 2 100% $HVL_WORKSPACE_PATH/linux-sd.wic
#export SDLOOPDEV=$(basename $('"losetup |grep $HVL_WORKSPACE_PATH/linux-sd.wic|cut -d ' ' -f 1"' ))
#e2fsck -f /dev/mapper/${SDLOOPDEV}p2
#resize2fs /dev/mapper/${SDLOOPDEV}p2

mkdir -p $HVL_WORKSPACE_PATH/out/images
cp -L -r $HVL_WORKSPACE_PATH/xilinx-zcu102-2020.2/pre-built/linux/images/ $HVL_WORKSPACE_PATH/out/

if [ $BUILD_SD -eq 1 ]; then
	cp $HOMEDIR/make-targets-helper $HVL_WORKSPACE_PATH/out/
	rm -r $HVL_WORKSPACE_PATH/out/sd
	mkdir $HVL_WORKSPACE_PATH/out/sd
	
	BOOT_DIR=$HVL_WORKSPACE_PATH/out/boot
	ROOT_DIR=$HVL_WORKSPACE_PATH/out/rootfs
	
	cd $HVL_WORKSPACE_PATH/out
	rm -r $BOOT_DIR
	rm -r $ROOT_DIR
	
	mkdir $BOOT_DIR
	mkdir $ROOT_DIR

	chmod -R 777 $HVL_WORKSPACE_PATH/out
	cd $HVL_WORKSPACE_PATH/out/images
	cp BOOT.BIN boot.scr $BOOT_DIR
	tar xzf rootfs.tar.gz -C $ROOT_DIR

	cd $HVL_WORKSPACE_PATH/out/tftp
	cp Image $BOOT_DIR
	cp dtb.dtb $BOOT_DIR/system.dtb

	cd $HVL_WORKSPACE_PATH/out
	cp -a target/* $ROOT_DIR

	chmod +x $ROOT_DIR/chr_setup.sh
	chroot $ROOT_DIR bash -c /chr_setup.sh
	$HOMEDIR/make-image-targets $HVL_WORKSPACE_PATH/out/ $HVL_WORKSPACE_PATH/out/sd
	
	chmod -R 777 $HVL_WORKSPACE_PATH/out
fi

exit 0

