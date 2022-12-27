# Raspberry Pi PXE Bootstrapping script

This script is an opinionated helper to bootstrap and configure Raspberry Pi computers to boot from wired network via PXE (Preboot eXecution Environment). I am developing it along writing a [more detailed blog post](https://krgr.dev/blog/raspberry-pi-pxe-kubernetes-cluster/) about out how to bootstrap manually. It is currently work in progress and only tested on Raspberry Pi 4 with Raspberry Pi OS Lite (64 bit, Debian Bullseye). It does the following things:

 * Upgrade system packages
 * Install unattended upgrades
 * Deactivate wlan
 * Deactivate swap
 * Switch network management to systemd-networkd
 * Switch network address resolution to systemd-resolved
 * Configure network interface
 * Initialize remote filesystems
 * Configure filesystem table and boot options
 * Update network boot EEPROM

## Usage

You can execute the script directly from the repository with the following command.

```bash
sh -c "$(curl -sL https://raw.githubusercontent.com/krgr/raspberry-pi-pxe-bootstrap/main/install.sh)"
```

If you clone the repository locally, you can run it locally via `./install.sh`.

The script by default presents a menu that allows you to select to (b)ootstrap netwoork boot, (c)heck bootloader config, or (e)exit. It will ask for reboots, and you need to run the script multiple (3) times to finish the full bootstrapping. if you want to execute just parts of the script, you can pass the corresponding functions as a parameter. The accepted parameters are:

 * bootstrap: simply bypassing the menu and starting a full bootstrap
 * update_system: update packages, install unattended upgrades
 * disable_wifi: disable wpa_supplicant, configure disabled wifi
 * disable_swap: disables the local swap file
 * switch_network_daemon: switches from dhcpcd and openresolv to systemd-networkd and -resolved
 * init_remote_filesystems: configures and initializes remote root and boot partisions, flashes EEPROM
 * bootloader_config: check / print bootloader config

Example:
```bash
./install.sh update_system
```

### Environment variables

The script recognizes the following environment variables

 * NAS_IP: pass the default IP to use for mounting network storage during the NFS initialization, and for initial tftpboot (DHCP)
