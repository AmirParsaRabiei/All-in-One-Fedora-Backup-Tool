#!/bin/bash

# Function to handle errors
handle_error() {
    local error_message=$1
    echo "Error: $error_message" >&2
    exit 1
}

# Function to decrypt backup
decrypt_backup() {
    local encrypted_file=$1
    local decrypted_file=$2
    
    read -s -p "Enter decryption password: " passphrase
    echo
    
    if openssl enc -d -aes-256-cbc -in "$encrypted_file" -out "$decrypted_file" -pass pass:"$passphrase"; then
        echo "Backup decrypted successfully."
    else
        handle_error "Failed to decrypt the backup"
    fi
}

# Function to extract backup
extract_backup() {
    local archive=$1
    local destination=$2
    
    if tar -xzf "$archive" -C "$destination"; then
        echo "Backup extracted successfully."
    else
        handle_error "Failed to extract the backup"
    fi
}

# Function to restore specific directories
restore_directory() {
    local source=$1
    local destination=$2
    
    if [ -d "$source" ]; then
        if sudo rsync -avh --delete "$source/" "$destination/"; then
            echo "Restored $destination successfully."
        else
            handle_error "Failed to restore $destination"
        fi
    else
        echo "Warning: Source directory $source not found. Skipping."
    fi
}

# Function to restore packages
restore_packages() {
    local packages_file=$1
    
    if [ -f "$packages_file" ]; then
        if sudo dnf install -y $(cat "$packages_file"); then
            echo "Packages restored successfully."
        else
            handle_error "Failed to restore packages"
        fi
    else
        echo "Warning: Packages list file not found. Skipping package restoration."
    fi
}

# Function to restore Flatpak apps
restore_flatpak_apps() {
    local flatpak_file=$1
    
    if [ -f "$flatpak_file" ]; then
        if xargs -a "$flatpak_file" flatpak install -y; then
            echo "Flatpak apps restored successfully."
        else
            handle_error "Failed to restore Flatpak apps"
        fi
    else
        echo "Warning: Flatpak apps list file not found. Skipping Flatpak apps restoration."
    fi
}

# Function to restore pip packages
restore_pip_packages() {
    local requirements_file=$1
    
    if [ -f "$requirements_file" ]; then
        if pip install -r "$requirements_file"; then
            echo "Pip packages restored successfully."
        else
            handle_error "Failed to restore pip packages"
        fi
    else
        echo "Warning: Requirements file not found. Skipping pip packages restoration."
    fi
}

# Function to restore disk image
restore_disk_image() {
    local image_file=$1
    
    echo "Available disks:"
    lsblk
    
    read -p "Enter the disk to restore to (e.g., /dev/nvme1n1): " restore_disk
    
    if [ ! -b "$restore_disk" ]; then
        handle_error "Invalid disk. Please enter a valid block device."
    fi
    
    read -p "Are you sure you want to restore the image to $restore_disk? This will erase all data on the disk. (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        if sudo dd if="$image_file" of="$restore_disk" bs=4M status=progress; then
            echo "Disk image restored successfully."
        else
            handle_error "Failed to restore disk image"
        fi
    else
        echo "Disk image restoration cancelled."
    fi
}

# Function to restore Borg backup
restore_borg_backup() {
    local borg_repo=$1
    local restore_path=$2
    
    echo "Available Borg archives:"
    borg list "$borg_repo"
    
    read -p "Enter the archive name to restore: " archive_name
    
    if borg extract --progress "$borg_repo::$archive_name"; then
        echo "Borg backup restored successfully."
    else
        handle_error "Failed to restore Borg backup"
    fi
}

# Main script

echo "Fedora Backup Restore Script"
echo "============================"

# Find available backups
backups=$(find . -maxdepth 1 -type d -name "backup_*" -print)

if [ -z "$backups" ]; then
    handle_error "No backup folders found in the current directory."
fi

echo "Available backups:"
select backup_dir in $backups; do
    if [ -n "$backup_dir" ]; then
        echo "Selected backup: $backup_dir"
        break
    else
        echo "Invalid selection. Please try again."
    fi
done

# Check if the backup is encrypted
if [ -f "$backup_dir.tar.gz.enc" ]; then
    echo "Encrypted backup found. Decrypting..."
    decrypt_backup "$backup_dir.tar.gz.enc" "$backup_dir.tar.gz"
    
    echo "Extracting decrypted backup..."
    extract_backup "$backup_dir.tar.gz" "$backup_dir"
    rm "$backup_dir.tar.gz"  # Remove the decrypted archive after extraction
elif [ -f "$backup_dir.tar.gz" ]; then
    echo "Compressed backup found. Extracting..."
    extract_backup "$backup_dir.tar.gz" "$backup_dir"
elif [ ! -d "$backup_dir" ]; then
    handle_error "Backup directory not found or is not accessible."
fi

# Determine the backup type
if [ -d "$backup_dir/borg_repo" ]; then
    backup_type="borg"
elif [ -f "$backup_dir/image/disk-image.img" ]; then
    backup_type="disk_image"
else
    backup_type="manual"
fi

echo "Detected backup type: $backup_type"

case $backup_type in
    "manual")
        echo "Select components to restore:"
        options=("System configuration (/etc)" "Var directory (/var)" "Opt directory (/opt)" "User configuration (~/.config)" "Home directory" "Browser data" "GNOME extensions" "Installed packages" "Pip packages" "Database dumps" "System logs" "All of the above")
        
        select opt in "${options[@]}"
        do
            case $opt in
                "System configuration (/etc)")
                    restore_directory "$backup_dir/etc" "/etc"
                    ;;
                "Var directory (/var)")
                    restore_directory "$backup_dir/var" "/var"
                    ;;
                "Opt directory (/opt)")
                    restore_directory "$backup_dir/opt" "/opt"
                    ;;
                "User configuration (~/.config)")
                    restore_directory "$backup_dir/config" "$HOME/.config"
                    ;;
                "Home directory")
                    restore_directory "$backup_dir/home" "$HOME"
                    ;;
                "Browser data")
                    restore_directory "$backup_dir/mozilla" "$HOME/.mozilla"
                    restore_directory "$backup_dir/google-chrome" "$HOME/.config/google-chrome"
                    restore_directory "$backup_dir/microsoft-edge" "$HOME/.config/microsoft-edge"
                    ;;
                "GNOME extensions")
                    restore_directory "$backup_dir/gnome-extensions" "$HOME/.local/share/gnome-shell/extensions"
                    sudo restore_directory "$backup_dir/gnome-extensions/system" "/usr/share/gnome-shell/extensions"
                    ;;
                "Installed packages")
                    restore_packages "$backup_dir/rpm-packages-list.txt"
                    restore_flatpak_apps "$backup_dir/flatpak-apps-list.txt"
                    ;;
                "Pip packages")
                    restore_pip_packages "$backup_dir/requirements.txt"
                    ;;
                "Database dumps")
                    echo "Restoring database dumps..."
                    # Add specific commands to restore database dumps
                    ;;
                "System logs")
                    restore_directory "$backup_dir/system_logs" "/var/log"
                    ;;
                "All of the above")
                    restore_directory "$backup_dir/etc" "/etc"
                    restore_directory "$backup_dir/var" "/var"
                    restore_directory "$backup_dir/opt" "/opt"
                    restore_directory "$backup_dir/config" "$HOME/.config"
                    restore_directory "$backup_dir/home" "$HOME"
                    restore_directory "$backup_dir/mozilla" "$HOME/.mozilla"
                    restore_directory "$backup_dir/google-chrome" "$HOME/.config/google-chrome"
                    restore_directory "$backup_dir/microsoft-edge" "$HOME/.config/microsoft-edge"
                    restore_directory "$backup_dir/gnome-extensions" "$HOME/.local/share/gnome-shell/extensions"
                    sudo restore_directory "$backup_dir/gnome-extensions/system" "/usr/share/gnome-shell/extensions"
                    restore_packages "$backup_dir/rpm-packages-list.txt"
                    restore_flatpak_apps "$backup_dir/flatpak-apps-list.txt"
                    restore_pip_packages "$backup_dir/requirements.txt"
                    echo "Restoring database dumps..."
                    # Add specific commands to restore database dumps
                    restore_directory "$backup_dir/system_logs" "/var/log"
                    break
                    ;;
                *) echo "Invalid option $REPLY";;
            esac
        done
        ;;
    "disk_image")
        restore_disk_image "$backup_dir/image/disk-image.img"
        ;;
    "borg")
        read -p "Enter the path to restore Borg backup: " restore_path
        restore_borg_backup "$backup_dir/borg_repo" "$restore_path"
        ;;
esac

echo "Restore process completed."