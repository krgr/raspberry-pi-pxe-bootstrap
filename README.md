# Raspberry Pi PXE Bootstrapping script

This script is an opinionated helper to bootstrap and configure Raspberry Pi computers to boot from wired network via PXE (Preboot eXecution Environment). It will and is currently work in progress:

 * Deactivate wlan
 * Deactivate swap
 * Switch network management to systemd-networks
 * Switch network address resolution to systwmd-resolved
 * Configure network interface
 * Initialize remote filesystems
 * TODO: Configure filesystem table and boot options
 * TODO: Update network boot EEPROM

## Usage

You can execute the script directly from the repository with the following command.

```bash
sh -c "$(curl -sL https://raw.githubusercontent.com/krgr/raspberry-pi-pxe-bootstrap/main/install.sh)"
```

If you clone the repository locally, you can run it locally via `./install.sh`.

### Environment variables

The script recognizes the following environment variables

 * NAS_IP: pass the default IP to use for mounting network storage during the NFS initialization.
 * TODO: TFTP_IP: pass the default IP for the TFTP / DHCP server

