#!/bin/bash

# Function to handle errors
handle_error() {
    local error_message=$1
    echo "Error: $error_message" >> "restore_error.log"
    echo "Error occurred. Check restore_error.log for details."
}

# Function to prompt for user confirmation
confirm() {
    while true; do
        read -p "$1 (Y/n): " yn
        case ${yn:-Y} in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Function to decrypt the backup
decrypt_backup() {
    local encrypted_file=$1
    local output_file=$2

    read -sp "Enter the decryption passphrase: " passphrase
    echo

    if openssl enc -d -aes-256-cbc -in "$encrypted_file" -out "$output_file" -pass pass:"$passphrase"; then
        echo "Backup decrypted successfully."
    else
        handle_error "Failed to decrypt the backup"
        exit 1
    fi
}

# Function to extract the backup
extract_backup() {
    local archive=$1
    local destination=$2

    if tar -xzf "$archive" -C "$destination"; then
        echo "Backup extracted successfully."
    else
        handle_error "Failed to extract the backup"
        exit 1
    fi
}

# Main restore process
echo "Welcome to the Restore Script"
echo "Please ensure this script is in the same directory as your backup files."

# Prompt for restore type
echo "Choose restore type:"
echo "1) Restore from disk image"
echo "2) Restore from manual backup"
read -p "Enter choice [1-2]: " restore_type

case $restore_type in
    1)
        echo "Restoring from disk image..."
        
        # List available disk image backups
        image_backups=$(ls *image*.img.enc 2>/dev/null)
        if [ -z "$image_backups" ]; then
            echo "No disk image backups found."
            exit 1
        fi
        
        echo "Available disk image backups:"
        select image in $image_backups; do
            if [ -n "$image" ]; then
                break
            else
                echo "Invalid selection. Please try again."
            fi
        done
        
        # Decrypt the disk image
        decrypt_backup "$image" "${image%.enc}"
        
        # Prompt for target disk
        lsblk
        read -p "Enter the target disk to restore to (e.g., /dev/sda): " target_disk
        
        if confirm "Are you sure you want to restore the image to $target_disk? This will erase all data on the disk."; then
            if sudo dd if="${image%.enc}" of="$target_disk" bs=4M status=progress; then
                echo "Disk image restored successfully."
            else
                handle_error "Failed to restore disk image"
            fi
        fi
        ;;
    2)
        echo "Restoring from manual backup..."
        
        # List available manual backups
        manual_backups=$(ls backup_*.tar.gz.enc 2>/dev/null)
        if [ -z "$manual_backups" ]; then
            echo "No manual backups found."
            exit 1
        fi
        
        echo "Available manual backups:"
        select backup in $manual_backups; do
            if [ -n "$backup" ]; then
                break
            else
                echo "Invalid selection. Please try again."
            fi
        done
        
        # Decrypt and extract the backup
        decrypt_backup "$backup" "${backup%.enc}"
        extract_backup "${backup%.enc}" "."
        
        # Restore specific components
        backup_dir="${backup%.tar.gz.enc}"
        
        if [ -d "$backup_dir/etc" ] && confirm "Restore system configuration files (/etc)?"; then
            sudo rsync -avh --delete "$backup_dir/etc/" /etc/
        fi
        
        if [ -d "$backup_dir/var" ] && confirm "Restore /var directory?"; then
            sudo rsync -avh --delete "$backup_dir/var/" /var/
        fi
        
        if [ -d "$backup_dir/opt" ] && confirm "Restore /opt directory?"; then
            sudo rsync -avh --delete "$backup_dir/opt/" /opt/
        fi
        
        if [ -d "$backup_dir/config" ] && confirm "Restore user-specific configuration files (~/.config)?"; then
            rsync -avh --delete "$backup_dir/config/" "$HOME/.config/"
        fi
        
        if [ -d "$backup_dir/home" ] && confirm "Restore home directory?"; then
            rsync -avh --delete "$backup_dir/home/" "$HOME/"
        fi
        
        if [ -d "$backup_dir/mozilla" ] && confirm "Restore Firefox data?"; then
            rsync -avh --delete "$backup_dir/mozilla/" "$HOME/.mozilla/"
        fi
        
        if [ -d "$backup_dir/google-chrome" ] && confirm "Restore Chrome data?"; then
            rsync -avh --delete "$backup_dir/google-chrome/" "$HOME/.config/google-chrome/"
        fi
        
        if [ -d "$backup_dir/microsoft-edge" ] && confirm "Restore Edge data?"; then
            rsync -avh --delete "$backup_dir/microsoft-edge/" "$HOME/.config/microsoft-edge/"
        fi
        
        if [ -d "$backup_dir/gnome-extensions" ] && confirm "Restore GNOME extensions?"; then
            rsync -avh --delete "$backup_dir/gnome-extensions/" "$HOME/.local/share/gnome-shell/extensions/"
            sudo rsync -avh --delete "$backup_dir/gnome-extensions/system/" /usr/share/gnome-shell/extensions/
        fi
        
        if [ -f "$backup_dir/rpm-packages-list.txt" ] && confirm "Restore RPM packages?"; then
            sudo dnf install $(cat "$backup_dir/rpm-packages-list.txt")
        fi
        
        if [ -f "$backup_dir/flatpak-apps-list.txt" ] && confirm "Restore Flatpak applications?"; then
            while read -r app; do
                flatpak install -y "$app"
            done < "$backup_dir/flatpak-apps-list.txt"
        fi
        
        if [ -f "$backup_dir/requirements.txt" ] && confirm "Restore pip packages?"; then
            pip install -r "$backup_dir/requirements.txt"
        fi
        
        if [ -d "$backup_dir/database_dumps" ] && confirm "Restore database dumps?"; then
            if [ -f "$backup_dir/database_dumps/mysql_dump.sql" ]; then
                sudo mysql < "$backup_dir/database_dumps/mysql_dump.sql"
            fi
            if [ -f "$backup_dir/database_dumps/postgresql_dump.sql" ]; then
                sudo -u postgres psql < "$backup_dir/database_dumps/postgresql_dump.sql"
            fi
        fi
        
        if [ -d "$backup_dir/system_logs" ] && confirm "Restore system logs?"; then
            sudo rsync -avh --delete "$backup_dir/system_logs/" /var/log/
        fi
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo "Restore process completed."