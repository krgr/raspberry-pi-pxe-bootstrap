# Raspberry Pi PXE Bootstrapping script

This script is an opinionated helper to bootstrap and configure Raspberry Pi computers to boot from wired network via PXE (Preboot eXecution Environment). It will:

 * Deactivate wlan
 * Deactivate swap
 * Switch network management to systemd-networks
 * Switch network address resolution to systwmd-resolved
 * Configure filesystem table and boot options
 * Update network boot EEPROM
