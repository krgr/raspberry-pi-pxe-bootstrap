#!/bin/sh

main() {
	OS=$(detect_os)

	log_info "OS: $OS"

	if [ -z "$OS" ]; then
#    if [ -z "$OS" ] || [ -z "$GOARCH" ] || [ -z "$GOOS" ] || [ -z "$NEXTDNS_BIN" ] || [ -z "$INSTALL_RELEASE" ]; then
		log_error "Cannot detect running environment."
		exit 1
	fi

	while true; do
		log_debug "Start install loop"
		menu \
			b "Bootstrap network boot " bootstrap \
			c "Check bootloader config" bootloader_config \
			e "Exit" exit
	done
}

bootstrap() {
	update_system
	disable_wifi
	disable_swap
	switch_network_daemon
	init_remote_filesystems
}

update_system() {
	print "Updating Package lists... "
	silent_exec asroot apt update
	println "Done"

	apt list --upgradable
	asroot apt full-upgrade
}

disable_wifi() {
	print "Disabling WiFi... "
	if systemctl is-active --quiet wpa_supplicant; then
		asroot systemctl disable wpa_supplicant
	fi
	if grep -q "dtoverlay=disable-wifi" /boot/config.txt; then
		println
		log_info "WiFi already disabled."
	elif [ -f /boot/config.txt.pxe.bak ]; then
		println
		log_error "Backup of config.txt file at /boot/config.txt.pxe.bak already exists. Please examine and remove to be able to proceed."
	else
		asroot sed -i.pxe.bak '/# Additional overlays and parameters are documented \/boot\/overlays\/README/a dtoverlay=disable-wifi' /boot/config.txt
		println "Done"
		ask_for_reboot
	fi
}

disable_swap() {
	print "Disabling swap... "
	asroot dphys-swapfile swapoff && asroot dphys-swapfile uninstall &&	silent_exec asroot systemctl disable dphys-swapfile
	println "Done"
}

switch_network_daemon() {
	stop_service "dhcpcd"
	disable_service "dhcpcd"
	enable_service "systemd-networkd"
	enable_service "systemd-resolved"
	start_service "systemd-resolved"
	link_resolve_stub
	configure_network
	restart_service "systemd-networkd"
	cleanup_system
	if [ "$(ask_bool 'Install Tailscale?' "true")" = "true" ]; then
		install_tailscale
	fi
}

cleanup_system() {
	asroot apt remove openresolv network-manager
	asroot apt autoremove
}

configure_network() {
	if [ -f /etc/systemd/network/20-wired.network ]; then
		log_info "Network already configured"
	else
		print "Configuring network... "
		networkctl | awk '/ether/ {print "[Match]\nName="$2"\n\n[Network]\nDHCP=yes\nKeepConfiguration=yes"}' | asroot tee /etc/systemd/network/20-wired.network > /dev/null
		println "Done"
	fi
}

link_resolve_stub() {
	asroot ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
}

init_remote_filesystems() {
	nfs_root="/nfs"
	hostname="$( hostname )"
	nas_volume="/volume1"
	tftp_folder="rpi-tftpboot"
	pxe_folder="rpi-pxe"
	nfs_options="proto=tcp,port=2049,rw,all_squash,anonuid=1001,anongid=1001"
	rasppi_serial="$( serial )"
	if [ -z $NAS_IP ]; then
		NAS_IP="192.168.133.21"
	fi
	while true; do
		input_nas_ip=$( input "Enter your NAS IP" $NAS_IP )
		NAS_IP=$( verify_ip $input_nas_ip )
		if [ -z $NAS_IP ]; then
			log_error "NAS IP $input_nas_ip is invalid."
		else
			break
		fi
	done

	# create remote root filesystem (/)
	pxefs="$nfs_root/$pxe_folder"
	asroot mkdir -p $pxefs
	asroot mount -t nfs -O $nfs_options $NAS_IP:$nas_volume/$pxe_folder $pxefs -vvv
	rootfs="$pxefs/$hostname"
	asroot mkdir -p $rootfs
	asroot rsync -xa --info=progress2 --exclude $nfs_root / $rootfs/

	# create remote tftpboot filesystem (/boot)
	tftpbootfs="$nfs_root/$tftp_folder"
	asroot mkdir -p $tftpbootfs
	asroot mount -t nfs -O $nfs_options $NAS_IP:$nas_volume/$tftp_folder $tftpbootfs -vvv

	if [ -f $tftpbootfs/bootcode.bin ]; then
		log_info "$tftpbootfs/bootcode.bin already exists. Skipping."
	else
		asroot cp /boot/bootcode.bin $tftpbootfs/
	fi
	bootfs=$tftpbootfs/$rasppi_serial
	asroot mkdir -p $bootfs
	asroot rsync -xa --info=progress2 /boot/* $bootfs/

	# configure remote filesystem table
	asroot sed -i.pxe.bak ' /boot \| \/ /d' "$rootfs/etc/fstab"
	echo  "$NAS_IP:$nas_volume/$tftp_folder/$rasppi_serial /boot nfs defaults,proto=tcp 0 0" | asroot tee -a "$rootfs/etc/fstab"

	# configure network boot kernel options
	echo "console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=$NAS_IP:$nas_volume/$pxe_folder/$hostname rw ip=dhcp elevator=deadline rootwait" | asroot tee "$bootfs/cmdline.txt"

	# configure EEPROM firmware
	firmware_folder="/lib/firmware/raspberrypi/bootloader/stable/"
	firmware=$( ls -r /lib/firmware/raspberrypi/bootloader/stable/pieeprom-2022-* | head -1 )
	cp $firmware pieeprom.bin
	cat >bootconf.txt << EOL
[all]
BOOT_UART=0
WAKE_ON_GPIO=1
POWER_OFF_ON_HALT=0
DHCP_TIMEOUT=45000
DHCP_REQ_TIMEOUT=4000
TFTP_FILE_TIMEOUT=30000
TFTP_IP=$NAS_IP
TFTP_PREFIX=0
ENABLE_SELF_UPDATE=1
DISABLE_HDMI=0
BOOT_ORDER=0x21
SD_BOOT_MAX_RETRIES=3
NET_BOOT_MAX_RETRIES=5 
EOL

	rpi-eeprom-config --out pieeprom-new.bin --config bootconf.txt pieeprom.bin
	println "Flashing Raspberry Pi EEPROM... "
	asroot rpi-eeprom-update -d -f ./pieeprom-new.bin
	println "Done"
	rm pieeprom.bin pieeprom-new.bin bootconf.txt
	ask_for_reboot
}

serial() {
	vcgencmd otp_dump | grep 28: | sed s/.*://g
}

verify_ip() {
	echo $@ | awk -F"." '$0 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $1 <=255 && $2 <=255 && $3 <= 255 && $4 <= 255'
}

ask_for_reboot() {
	if [ "$(ask_bool 'Reboot now?' "true")" = "true" ]; then
		asroot reboot
	fi
}

bootloader_config() {
	vcgencmd bootloader_config
}

install_tailscale() {
	silent_exec asroot apt update
	asroot apt install apt-transport-https
	curl -fsSL https://pkgs.tailscale.com/stable/raspbian/bullseye.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
	curl -fsSL https://pkgs.tailscale.com/stable/raspbian/bullseye.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
	asroot apt update
	asroot apt install tailscale
	asroot tailscale up --ssh
}

restart_service() {
	service=$1
	print "Restarting $service... "
	silent_exec asroot systemctl restart $service
	println "Done"
}

stop_service() {
	# Stop service
	service=$1
	if systemctl is-active --quiet $service; then
		print "Stopping $service... "
		silent_exec asroot systemctl stop $service
		println "Done"
	else
		log_info "$service already stopped."
	fi
}

start_service() {
	# Start service if not already started
	service=$1
	if systemctl is-active --quiet $service; then
		log_info "$service already started."
	else
		print "Starting $service... "
		silent_exec asroot systemctl start $service
		println "Done"
	fi
}

disable_service() {
	# Prevent service from starting after reboot
	service=$1
	if systemctl is-enabled --quiet $service; then
		print "Disabling $service... "
		silent_exec asroot systemctl disable $service
		println "Done"
	else
		log_info "$service already disabled."
	fi

}

enable_service() {
	# Enable service if not already enabled so it starts on every boot
	service=$1
	if systemctl is-enabled --quiet $service; then
		log_info "$service already enabled."
	else
		print "Enabling $service... "
		silent_exec asroot systemctl enable $service
		println "Done"
	fi
}

log_debug() {
	if [ "$DEBUG" = "1" ]; then
		printf "\033[30;1mDEBUG: %s\033[0m\n" "$*" >&2
	fi
}

log_info() {
	printf "INFO: %s\n" "$*" >&2
}

log_error() {
	printf "\033[31mERROR: %s\033[0m\n" "$*" >&2
}

print() {
	format=$1
	if [ $# -gt 0 ]; then
		shift
	fi
	# shellcheck disable=SC2059
	printf "$format" "$@" >&2
}

println() {
	format=$1
	if [ $# -gt 0 ]; then
		shift
	fi
	# shellcheck disable=SC2059
	printf "$format\n" "$@" >&2
}

doc() {
	# shellcheck disable=SC2059
	printf "\033[30;1m%s\033[0m\n" "$*" >&2
}
input() {
	prompt=$1
	default=$2
	if [ $# -gt 1 ]; then
		print "%s (default=%s):" "$prompt" "$default"
	elif [ $# -gt 0 ]; then
		print "%s: " "$prompt"
	fi
	read -r choice
	if [ -z "$choice" ]; then
		choice=$default
	fi
	echo $choice
}

menu() {
	while true; do
		n=0
		default=
		# output menu
		for item in "$@"; do
			case $((n%3)) in
			0) # key
				key=$item
				if [ -z "$default" ]; then
					default=$key
				fi
				;;
			1) # description
				echo "$key) $item"
				;;
			esac
			n=$((n+1))
		done
		print "Choice (default=%s): " "$default"
		read -r choice
		if [ -z "$choice" ]; then
			choice=$default
		fi
		n=0
		for item in "$@"; do
			case $((n%3)) in
			0) # key
				key=$item
				;;
			2) # command
				if [ "$key" = "$choice" ]; then
					if ! "$item"; then
						log_error "$item: exit $?"
					fi
					break 2
				fi
				;;
			esac
			n=$((n+1))
		done
		echo "Invalid choice"
	done
}

ask_bool() {
	msg=$1
	default=$2
	case $default in
	true)
		msg="$msg [Y|n]: "
		;;
	false)
		msg="$msg [y|N]: "
		;;
	*)
		msg="$msg (y/n): "
	esac
	while true; do
		print "%s" "$msg"
		read -r answer
		if [ -z "$answer" ]; then
			answer=$default
		fi
		case $answer in
		y|Y|yes|YES|true)
			echo "true"
			return 0
			;;
		n|N|no|NO|false)
			echo "false"
			return 0
			;;
		*)
			echo "Invalid input, use yes or no"
			;;
		esac
	done
}

asroot() {
	# Some platform (merlin) do not have the "id" command and $USER report a non root username with uid 0.
	if [ "$(grep '^Uid:' /proc/$$/status 2>/dev/null|cut -f2)" = "0" ] || [ "$USER" = "root" ] || [ "$(id -u 2>/dev/null)" = "0" ]; then
		"$@"
	elif [ "$(command -v sudo 2>/dev/null)" ]; then
		sudo "$@"
	else
		echo "Root required"
		su -m root -c "$*"
	fi
}

silent_exec() {
	if [ "$DEBUG" = 1 ]; then
		"$@"
	else
		if ! out=$("$@" 2>&1); then
			rt=$?
			println "\033[30;1m%s\033[0m" "$out"
			return $rt
		fi
	fi
}

detect_os() {
	if [ "$FORCE_OS" ]; then
		echo "$FORCE_OS"; return 0
	fi
	case $(uname -s) in
	Linux)
		case $(uname -o) in
		GNU/Linux|Linux)
			if grep -q -e '^EdgeRouter' -e '^UniFiSecurityGateway' /etc/version 2> /dev/null; then
				echo "edgeos"; return 0
			fi
			if uname -u 2>/dev/null | grep -q '^synology'; then
				echo "synology"; return 0
			fi
			# shellcheck disable=SC1091
			dist=$(. /etc/os-release; echo "$ID")
			case $dist in
			ubios)
				if [ -z "$(command -v podman)" ]; then
					log_error "This version of UnifiOS is not supported. Make sure you run version 1.7.0 or above."
					return 1
				fi
				echo "$dist"; return 0
				;;
			debian|ubuntu|elementary|raspbian|centos|fedora|rhel|arch|manjaro|openwrt|clear-linux-os|linuxmint|opensuse-tumbleweed|opensuse-leap|opensuse|solus|pop|neon|overthebox|sparky|vyos|void|alpine|Deepin|gentoo|steamos)
				echo "$dist"; return 0
				;;
			esac
			# shellcheck disable=SC1091
			for dist in $(. /etc/os-release; echo "$ID_LIKE"); do
				case $dist in
				debian|ubuntu|rhel|fedora|openwrt)
					log_debug "Using ID_LIKE"
					echo "$dist"; return 0
					;;
				esac
			done
			;;
		ASUSWRT-Merlin*)
			echo "asuswrt-merlin"; return 0
			;;
		DD-WRT)
			echo "ddwrt"; return 0
		esac
		;;
	Darwin)
		echo "darwin"; return 0
		;;
	FreeBSD)
		if [ -f /etc/platform ]; then
			case $(cat /etc/platform) in
			pfSense)
				echo "pfsense"; return 0
				;;
			esac
		fi
		if [ -x /usr/local/sbin/opnsense-version ]; then
			case $(/usr/local/sbin/opnsense-version -N) in
			OPNsense)
				echo "opnsense"; return 0
				;;
			esac
		fi
		echo "freebsd"; return 0
		;;
	NetBSD)
		echo "netbsd"; return 0
		;;
	OpenBSD)
		echo "openbsd"; return 0
		;;
	*)
	esac
	log_error "Unsupported OS: $(uname -o) $(grep ID "/etc/os-release" 2>/dev/null | xargs)"
	return 1
}

umask 0022
main