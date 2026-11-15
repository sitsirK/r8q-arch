#!/bin/sh
# Assemble the NCM USB gadget (g1) and bind the dwc3 UDC. r8q dwc3 peripheral is
# built-in and needs no extcon/module tricks (unlike garnet). usb0 = 172.16.42.1
# (address set by systemd-networkd, 20-usb0.network).
set -e
UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
[ -n "$UDC" ] || { echo "r8q-gadget: no UDC found"; exit 1; }
mount -t configfs none /sys/kernel/config 2>/dev/null || true
G=/sys/kernel/config/usb_gadget/g1
mkdir -p "$G/strings/0x409" "$G/configs/c.1/strings/0x409" "$G/functions/ncm.usb0"
echo 0x1d6b > "$G/idVendor"
echo 0x0104 > "$G/idProduct"
echo "r8q-mainline"    > "$G/strings/0x409/product"
echo "Samsung"         > "$G/strings/0x409/manufacturer"
echo "r8q0001"         > "$G/strings/0x409/serialnumber"
echo "ncm"             > "$G/configs/c.1/strings/0x409/configuration"
ln -sf "$G/functions/ncm.usb0" "$G/configs/c.1/" 2>/dev/null || true

# Close the MAX77705 MUIC data switch (i2c0 @0x25, opcode CTRL1_W 0x06,
# value 0x09 = COMN1SW/COMP2SW -> USB; Samsung's com_to_usb_ap). After a
# reboot it reads 0x3f (both lines OPEN) and the host never sees the gadget
# until the cable is replugged; mainline has no MUIC driver to close it.
# Needs i2c-tools; i2c0 comes up with r8q-touch/r8q-battery, so retry.
if command -v i2ctransfer >/dev/null; then
	for i in 1 2 3 4 5 6 7 8 9 10; do
		i2ctransfer -y 0 w3@0x25 0x21 0x06 0x09 2>/dev/null &&
			i2cset -y 0 0x25 0x41 0x00 2>/dev/null &&
			{ echo "r8q-gadget: MUIC switch set to USB"; break; }
		sleep 1
	done
else
	echo "r8q-gadget: i2c-tools missing, MUIC switch left alone (replug after reboot)"
fi

echo "$UDC" > "$G/UDC"
echo "r8q-gadget: bound NCM gadget to $UDC"
