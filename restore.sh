#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

# Function to handle errors
handle_error() {
    local error_message=$1
    echo "Error: $error_message" >&2
    exit 1
}

# Function to check required commands
check_required_commands() {
    local commands=("rsync" "tar" "openssl" "borg" "flatpak" "pip" "dd")
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            handle_error "Required command '$cmd' not found. Please install it and try again."
        fi
    done
}

# Function to find the most recent backup
find_latest_backup() {
    local latest_backup=$(find . -maxdepth 1 -type d -name "backup_*" | sort -r | head -n1)
    if [ -z "$latest_backup" ]; then
        handle_error "No backup folder found in the current directory."
    fi
    echo "$latest_backup"
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

# ... [rest of the functions remain the same] ...

# Main script

echo "Fedora Backup Restore Script"
echo "============================"

# Check for required commands
check_required_commands

# Find the latest backup
backup_dir=$(find_latest_backup)
echo "Found backup directory: $backup_dir"

# Determine if the backup is encrypted
if [ -f "$backup_dir.tar.gz.enc" ]; then
    echo "Encrypted backup found. Decrypting..."
    decrypt_backup "$backup_dir.tar.gz.enc" "$backup_dir.tar.gz"
    extract_backup "$backup_dir.tar.gz" "$backup_dir"
    rm "$backup_dir.tar.gz"  # Remove the decrypted archive after extraction
elif [ -f "$backup_dir.tar.gz" ]; then
    echo "Compressed backup found. Extracting..."
    extract_backup "$backup_dir.tar.gz" "$backup_dir"
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
        options=(
            "System configuration (/etc)"
            "Var directory (/var)"
            "Opt directory (/opt)"
            "User configuration (~/.config)"
            "Home directory"
            "Browser data"
            "GNOME extensions"
            "Installed packages"
            "Pip packages"
            "Database dumps"
            "System logs"
            "All of the above"
        )
        
        PS3="Enter your choice (1-${#options[@]}): "
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
                    restore_database_dumps "$backup_dir/database_dumps"
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
                    restore_database_dumps "$backup_dir/database_dumps"
                    restore_directory "$backup_dir/system_logs" "/var/log"
                    break
                    ;;
                *) echo "Invalid option $REPLY";;
            esac
            REPLY=
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
echo "Please reboot your system to ensure all changes take effect."