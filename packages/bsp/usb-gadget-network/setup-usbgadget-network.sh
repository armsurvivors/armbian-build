#!/bin/bash

deviceinfo_name="USB Gadget Network"
deviceinfo_manufacturer="Armbian"
#deviceinfo_usb_idVendor=
#deviceinfo_usb_idProduct=
#deviceinfo_usb_serialnumber=

# Optional settings, eg. USB_GADGET_ACM=yes to add an ACM serial function (ttyGS0 on the device),
# USB_GADGET_IP=dhcp to not run the DHCP server (the device is a DHCP client on usb0, eg. bridged on the host)
# shellcheck disable=SC1091
[ -f /etc/default/usb-gadget-network ] && . /etc/default/usb-gadget-network

setup_usb_network_configfs() {
	# See: https://www.kernel.org/doc/Documentation/usb/gadget_configfs.txt
	CONFIGFS=/sys/kernel/config/usb_gadget

	if ! [ -e "$CONFIGFS" ]; then
		echo "  $CONFIGFS does not exist, skipping configfs usb gadget"
		return
	fi

	if [ -e "$CONFIGFS/g1" ]; then
		echo "  $CONFIGFS/g1 already exists, skipping configfs usb gadget"
		return
	fi

	# Default values for USB-related deviceinfo variables
	usb_idVendor="${deviceinfo_usb_idVendor:-0x1D6B}"   # Linux Foundation
	usb_idProduct="${deviceinfo_usb_idProduct:-0x0103}" # NCM (Ethernet) Gadget
	if [ "${USB_GADGET_ACM}" = "yes" ]; then
		usb_idProduct="${deviceinfo_usb_idProduct:-0x0104}" # Multifunction Composite Gadget
	fi
	usb_serialnumber="${deviceinfo_usb_serialnumber:-0123456789}"
	usb_network_function="ncm.usb0"

	echo "  Setting up an USB gadget through configfs"
	# Create an usb gadet configuration
	mkdir $CONFIGFS/g1 || echo "  Couldn't create $CONFIGFS/g1"
	echo "$usb_idVendor" > "$CONFIGFS/g1/idVendor"
	echo "$usb_idProduct" > "$CONFIGFS/g1/idProduct"
	echo 0x0100 > "$CONFIGFS/g1/bcdDevice"
	echo 0x0200 > "$CONFIGFS/g1/bcdUSB"

	# Create english (0x409) strings
	mkdir $CONFIGFS/g1/strings/0x409 || echo "  Couldn't create $CONFIGFS/g1/strings/0x409"

	# shellcheck disable=SC2154
	echo "$deviceinfo_manufacturer" > "$CONFIGFS/g1/strings/0x409/manufacturer"
	echo "$usb_serialnumber" > "$CONFIGFS/g1/strings/0x409/serialnumber"
	# shellcheck disable=SC2154
	echo "$deviceinfo_name" > "$CONFIGFS/g1/strings/0x409/product"

	# Create network function.
	mkdir $CONFIGFS/g1/functions/"$usb_network_function" ||
		echo "  Couldn't create $CONFIGFS/g1/functions/$usb_network_function"

	# Fixed MAC addresses when the device is a DHCP client, so the host interface name and the lease are stable
	if [ "${USB_GADGET_IP}" = "dhcp" ]; then
		set_usbgadget_macs "$CONFIGFS/g1/functions/$usb_network_function"
	fi

	# Optional ACM serial function
	if [ "${USB_GADGET_ACM}" = "yes" ]; then
		mkdir $CONFIGFS/g1/functions/acm.GS0 ||
			echo "  Couldn't create $CONFIGFS/g1/functions/acm.GS0"
	fi

	# Create configuration instance for the gadget
	mkdir $CONFIGFS/g1/configs/c.1 ||
		echo "  Couldn't create $CONFIGFS/g1/configs/c.1"
	echo 250 > $CONFIGFS/g1/configs/c.1/MaxPower
	mkdir $CONFIGFS/g1/configs/c.1/strings/0x409 ||
		echo "  Couldn't create $CONFIGFS/g1/configs/c.1/strings/0x409"
	echo "NCM Configuration" > $CONFIGFS/g1/configs/c.1/strings/0x409/configuration ||
		echo "  Couldn't write configration name"

	# Link the network instance to the configuration
	ln -s $CONFIGFS/g1/functions/"$usb_network_function" $CONFIGFS/g1/configs/c.1 ||
		echo "  Couldn't symlink $usb_network_function"
	if [ "${USB_GADGET_ACM}" = "yes" ]; then
		ln -s $CONFIGFS/g1/functions/acm.GS0 $CONFIGFS/g1/configs/c.1 ||
			echo "  Couldn't symlink acm.GS0"
	fi

	# Check if there's an USB Device Controller
	if [ -z "$(ls /sys/class/udc)" ]; then
		echo "  No USB Device Controller available"
		return
	fi

	# Link the gadget instance to an USB Device Controller. This activates the gadget.
	# See also: https://github.com/postmarketOS/pmbootstrap/issues/338
	# shellcheck disable=SC2005
	echo "$(ls /sys/class/udc)" > $CONFIGFS/g1/UDC || echo "  Couldn't write UDC"
}

# Locally administered MACs derived from the device serial (Android bootloader, DT or machine-id)
set_usbgadget_macs() {
	local func="$1" seed="" hash
	seed="$(sed -n 's/.*androidboot.serialno=\([^ ]*\).*/\1/p' /proc/cmdline)"
	[ -z "$seed" ] && [ -r /sys/firmware/devicetree/base/serial-number ] && seed="$(tr -d '\0' < /sys/firmware/devicetree/base/serial-number)"
	[ -z "$seed" ] && [ -r /etc/machine-id ] && seed="$(cat /etc/machine-id)"
	if [ -z "$seed" ]; then
		echo "  No device serial found, using random MAC addresses"
		return
	fi
	hash="$(echo "$seed" | md5sum | cut -c1-8)"
	local base
	base="$(echo "$hash" | sed 's/\(..\)\(..\)\(..\)\(..\)/\1:\2:\3:\4/')"
	echo "02:${base}:01" > "$func/dev_addr" || echo "  Couldn't set dev_addr"
	echo "02:${base}:02" > "$func/host_addr" || echo "  Couldn't set host_addr"
}

set_usbgadget_ipaddress() {
	local host_ip="${unudhcpd_host_ip:-172.16.42.1}"
	local client_ip="${unudhcpd_client_ip:-172.16.42.2}"
	unudhcpd_pid=$(pgrep unudhcpd)
	if [ "x$unudhcpd_pid" != "x" ]; then
		echo "unudhcpd process already exists, skip setting usb gadget ip, unudhcpd_pid is $unudhcpd_pid"
		return
	fi
	echo "Starting unudhcpd service with server ip $host_ip, client ip: $client_ip"
	# Get usb interface
	INTERFACE=""
	ip a add "${host_ip}/255.255.0.0" dev usb0 2> /dev/null && ip link set usb0 up && INTERFACE=usb0
	if [ -z $INTERFACE ]; then
		ip a add "${host_ip}/255.255.0.0" dev eth0 2> /dev/null && ip link set eth0 up && INTERFACE=eth0
	fi

	if [ -z $INTERFACE ]; then
		echo "  Could not find an interface to run a dhcp server on"
		echo "  Interfaces:"
		ip link
		return
	fi

	echo "  Using interface $INTERFACE"
	echo "  Starting the DHCP daemon"
	ip a show $INTERFACE > /var/log/unudhcpd.log
	nohup /usr/bin/unudhcpd -i "$INTERFACE" -s "$host_ip" -c "$client_ip" >> /var/log/unudhcpd.log 2>&1 &
	return
}
setup_usb_network_configfs
if [ "${USB_GADGET_IP}" = "dhcp" ]; then
	ip link set usb0 up 2> /dev/null || echo "  Couldn't bring up usb0"
else
	set_usbgadget_ipaddress
fi
