# Raspberry Pi PXE Bootstrapping script

This script is an opinionated helper to bootstrap and configure Raspberry Pi computers to boot from wired network via PXE (Preboot eXecution Environment). It will and is currently work in progress:

 * Deactivate wlan
 * Deactivate swap
 * Switch network management to systemd-networks
 * Switch network address resolution to systwmd-resolved
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
 * update_system: (1. step) update packages, install unattended upgrades
 * disable_wifi: disable wpa_supplicant, configure disabled wifi
 * disable_swap: disables the local swap file
 * switch_network_daemon: switches from dhcpcd and openresolv to systemd-networkd and -resolved
 * init_remote_filesystems: configures and initializes remote root and boot partisions, flashes EEPROM
 * bootloader_config: check / print bootloader config

Example:
```bash
./install update_system
```

### Environment variables

The script recognizes the following environment variables

 * NAS_IP: pass the default IP to use for mounting network storage during the NFS initialization, and for initial tftpboot (DHCP)
