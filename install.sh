#!/bin/sh

main() {
	update_system
	disable_wifi
	configure_pxe
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
		if [ "$(ask_bool 'Reboot now?' "true")" = "true" ]; then
            asroot reboot
        fi
	fi
}

configure_pxe() {
	disable_swap
	switch_network_daemon
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

restart_service() {
	service=$1
	print "Restarting $service... "
	asroot systemctl restart $service
	println "Done"
}

stop_service() {
	# Stop service
	service=$1
	if systemctl is-active --quiet $service; then
		print "Stopping $service... "
		asroot systemctl stop $service
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
		asroot systemctl start $service
		println "Done"
	fi
}

disable_service() {
	# Prevent service from starting after reboot
	service=$1
	if systemctl is-enabled --quiet $service; then
		print "Disabling $service... "
		asroot systemctl disable $service
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
		asroot systemctl enable $service
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

menu() {
    while true; do
        n=0
        default=
        for item in "$@"; do
            case $((n%3)) in
            0)
                key=$item
                if [ -z "$default" ]; then
                    default=$key
                fi
                ;;
            1)
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
            0)
                key=$item
                ;;
            2)
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

umask 0022
main