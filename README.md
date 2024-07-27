# Fedora Backup and Restore Scripts

This project provides comprehensive backup and restore scripts for Fedora systems. These scripts allow you to create full system backups, including system configurations, user data, installed packages, and more. They also provide options for restoring your system from these backups.

## TODO
- The script is quite long and complex. Consider breaking it down into smaller, modular functions for easier maintenance.
- Add more comments throughout the script to explain what each section does.
- Consider adding a dry-run option to show what would be backed up without actually performing the backup.
- Implement a more robust logging system, possibly writing to a separate log file in addition to the console output.
- Edit restore script

## Features

- Multiple backup types:
  - Manual backup (selective components)
  - Full disk image backup
  - Borg backup (efficient, deduplicated backups)
- Encryption support for enhanced security
- Compression to save storage space
- Restore functionality for all backup types
- Support for various system components:
  - System configuration files (/etc)
  - User home directories
  - Installed packages (RPM and Flatpak)
  - Browser data (Firefox, Chrome, Edge)
  - GNOME extensions
  - Database dumps
  - System logs
  - And more!

## Prerequisites

Ensure you have the following tools installed on your Fedora system:

- rsync
- tar
- openssl
- borg
- flatpak
- pip
- dd

You can install these using DNF:

```bash
sudo dnf install rsync tar openssl borgbackup flatpak python3-pip
```

## Usage

### Backup

1. Download the `backup.sh` script.
2. Make it executable:
   ```bash
   chmod +x backup.sh
   ```
3. Run the script with sudo privileges:
   ```bash
   sudo ./backup.sh
   ```
4. Follow the on-screen prompts to select your backup type and options.

### Restore

1. Download the `restore.sh` script.
2. Make it executable:
   ```bash
   chmod +x restore.sh
   ```
3. Ensure your backup files are in the same directory as the script.
4. Run the script with sudo privileges:
   ```bash
   sudo ./restore.sh
   ```
5. Follow the on-screen prompts to select components to restore.

## Backup Types

1. **Manual Backup**: Allows you to select specific components to back up.
2. **Disk Image**: Creates a full image of a selected disk or partition.
3. **Borg Backup**: Uses Borg to create efficient, deduplicated backups.

## Security

- The scripts offer an option to encrypt your backups using AES-256-CBC encryption.
- Make sure to remember your encryption password, as it's required for decryption during restore.

## Caution

- Always test the restore process in a safe environment before applying it to your main system.
- Ensure you have sufficient disk space for your backups.
- Regularly verify the integrity of your backups.

