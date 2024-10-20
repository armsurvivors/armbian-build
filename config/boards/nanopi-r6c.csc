# Rockchip RK3588S octa core 8GB RAM SoC eMMC 1x NVMe 1x USB3 1x USB2 1x 2.5GbE 1x GbE
BOARD_NAME="NanoPi R6C"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="ColorfulRhino"
BOOTCONFIG="nanopi-r6s-rk3588s_defconfig" # vendor name (same as R6S!), not standard, see hook below, set BOOT_SOC below to compensate
BOOT_SOC="rk3588"
KERNEL_TARGET="edge,current,vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
IMAGE_PARTITION_TABLE="gpt"
BOOT_FDT_FILE="rockchip/rk3588s-nanopi-r6c.dtb"
BOOT_SCENARIO="spl-blobs"

function post_family_tweaks__nanopi_r6c_naming_audios() {
	display_alert "$BOARD" "Renaming NanoPi R6C HDMI audio interface to human-readable form" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
		SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"'
	EOF
}

function post_family_tweaks__nanopi_r6c_naming_udev_network_interfaces() {
	display_alert "$BOARD" "Renaming NanoPi R6C network interfaces to 'wan' and 'lan'" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="fe1c0000.ethernet", NAME:="wan"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="0003:31:00.0", NAME:="lan"
	EOF
}

# Mainline U-Boot (for current and edge)
function post_family_config__nanopi_r6c_use_mainline_uboot() {
	if [[ "${BRANCH}" != "edge" && "${BRANCH}" != "current" ]]; then return 0; fi

	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"
	declare -g BOOTCONFIG="nanopi-r6c-rk3588s_defconfig" # Mainline defconfig, enables booting from NVMe

	declare -g BOOTDELAY=1                                       # Wait for UART interrupt to enter UMS/RockUSB mode etc
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git" # We ❤️ Mainline U-Boot
	declare -g BOOTBRANCH="tag:v2024.10"
	declare -g BOOTPATCHDIR="v2024.10"
	# Don't set BOOTDIR, allow shared U-Boot source directory for disk space efficiency

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# Disable stuff from rockchip64_common; we're using binman here which does all the work already
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}

# Mainline U-Boot configs (for current and edge)
function post_config_uboot_target__extra_configs_for_nanopi_r6c_uboot() {
	if [[ "${BRANCH}" != "edge" && "${BRANCH}" != "current" ]]; then return 0; fi

	display_alert "$BOARD" "u-boot configs for ${BOOTBRANCH} u-boot config BRANCH=${BRANCH}" "info"

	display_alert "u-boot for ${BOARD}" "u-boot: enable RNG / KASLRSEED" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_KASLRSEED # New!

	#display_alert "u-boot for ${BOARD}" "u-boot: enable preboot & flash user LED in preboot" "info"
	#run_host_command_logged scripts/config --enable CONFIG_USE_PREBOOT
	#run_host_command_logged scripts/config --set-str CONFIG_PREBOOT "'led led-1 on; sleep 0.1; led led-1 off'" # double quotes required due to run_host_command_logged's quirks

	display_alert "u-boot for ${BOARD}" "u-boot: enable EFI debugging command" "info"
	run_host_command_logged scripts/config --enable CMD_EFIDEBUG
	run_host_command_logged scripts/config --enable CMD_NVEDIT_EFI

	display_alert "u-boot for ${BOARD}" "u-boot: enable more compression support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LZO
	run_host_command_logged scripts/config --enable CONFIG_BZIP2
	run_host_command_logged scripts/config --enable CONFIG_ZSTD

	display_alert "u-boot for ${BOARD}" "u-boot: enable gpio LED support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LED
	run_host_command_logged scripts/config --enable CONFIG_LED_GPIO

	display_alert "u-boot for ${BOARD}" "u-boot: enable networking cmds" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_NFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_WGET
	run_host_command_logged scripts/config --enable CONFIG_CMD_DNS
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP_SACK

	# UMS, RockUSB, gadget stuff
	declare -a enable_configs=("CONFIG_CMD_USB_MASS_STORAGE" "CONFIG_USB_GADGET" "USB_GADGET_DOWNLOAD" "CONFIG_USB_FUNCTION_ROCKUSB" "CONFIG_USB_FUNCTION_ACM" "CONFIG_CMD_ROCKUSB" "CONFIG_CMD_USB_MASS_STORAGE")
	for config in "${enable_configs[@]}"; do
		display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable ${config}" "info"
		run_host_command_logged scripts/config --enable "${config}"
	done
	# Auto-enabled by the above, force off...
	run_host_command_logged scripts/config --disable USB_FUNCTION_FASTBOOT

	return 0
}
