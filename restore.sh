#!/bin/bash

# Utility Functions
handle_error() {
    local error_message=$1
    echo "Error: $error_message" >&2
    exit 1
}

confirm() {
    local prompt=$1
    while true; do
        read -p "$prompt (Y/n/A, default is Y): " yn
        case ${yn:-Y} in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            [Aa]* ) return 2;;
            * ) echo "Please answer yes, no, or all.";;
        esac
    done
}

log_section_report() {
    local section=$1
    local start_time=$2
    local end_time=$3
    echo "$section: completed in $(($end_time - $start_time)) seconds" >> "$restore_dir/restore_report.txt"
}

# Package Management
check_and_install_packages() {
    local required_packages=(rsync dd gzip dnf flatpak pip openssl borg ddrescue cmp)
    local missing_packages=()

    for package in "${required_packages[@]}"; do
        if ! command -v $package &> /dev/null; then
            missing_packages+=($package)
        fi
    done

    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo "The following packages are required: ${missing_packages[*]}"
        if confirm "Do you want to install them now?"; then
            if sudo -v; then
                sudo dnf install -y ${missing_packages[*]}
            else
                handle_error "sudo privileges required to install packages. Exiting."
            fi
        else
            handle_error "Required packages are missing. Exiting."
        fi
    fi
}

# Restore Functions
find_latest_backup() {
    local latest_backup=$(find . -maxdepth 1 -type d -name "backup_*" | sort -r | head -n1)
    if [ -z "$latest_backup" ]; then
        handle_error "No backup folder found in the current directory."
    fi
    echo "$latest_backup"
}

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

extract_backup() {
    local archive=$1
    local destination=$2
    
    if tar -xzf "$archive" -C "$destination"; then
        echo "Backup extracted successfully."
    else
        handle_error "Failed to extract the backup"
    fi
}

restore_directory() {
    local source=$1
    local destination=$2
    local section_start_time=$(date +%s)
    
    if sudo rsync -avh --delete "$source/" "$destination"; then
        echo "Directory $destination restored successfully."
        local section_end_time=$(date +%s)
        log_section_report "Restore $destination" $section_start_time $section_end_time
    else
        handle_error "Failed to restore directory $destination"
    fi
}

restore_packages() {
    local rpm_list=$1
    local flatpak_list=$2
    local pip_list=$3
    local section_start_time=$(date +%s)
    
    # Restore RPM packages
    if [ -f "$rpm_list" ]; then
        echo "Restoring RPM packages..."
        if sudo dnf install -y $(cat "$rpm_list"); then
            echo "RPM packages restored successfully."
        else
            handle_error "Failed to restore RPM packages"
        fi
    fi
    
    # Restore Flatpak packages
    if [ -f "$flatpak_list" ]; then
        echo "Restoring Flatpak packages..."
        if xargs -a "$flatpak_list" flatpak install -y; then
            echo "Flatpak packages restored successfully."
        else
            handle_error "Failed to restore Flatpak packages"
        fi
    fi
    
    # Restore pip packages
    if [ -f "$pip_list" ]; then
        echo "Restoring pip packages..."
        if pip install -r "$pip_list"; then
            echo "Pip packages restored successfully."
        else
            handle_error "Failed to restore pip packages"
        fi
    fi
    
    local section_end_time=$(date +%s)
    log_section_report "Restore packages" $section_start_time $section_end_time
}

restore_disk_image() {
    local image_file=$1
    local section_start_time=$(date +%s)
    
    echo "Available disks:"
    lsblk
    
    read -p "Enter the disk to restore to (e.g., /dev/sda): " target_disk
    
    if [ ! -b "$target_disk" ]; then
        handle_error "Invalid disk. Please enter a valid block device."
    fi
    
    if confirm "Are you sure you want to restore the disk image to $target_disk? This will erase all data on the disk."; then
        if sudo ddrescue -f "$image_file" "$target_disk"; then
            echo "Disk image restored successfully."
            local section_end_time=$(date +%s)
            log_section_report "Restore disk image" $section_start_time $section_end_time
        else
            handle_error "Failed to restore disk image"
        fi
    fi
}

restore_borg_backup() {
    local repo_path=$1
    local restore_path=$2
    local section_start_time=$(date +%s)
    
    if borg extract "$repo_path::$(borg list "$repo_path" | tail -n1 | cut -d' ' -f1)" "$restore_path"; then
        echo "Borg backup restored successfully to $restore_path."
        local section_end_time=$(date +%s)
        log_section_report "Restore Borg backup" $section_start_time $section_end_time
    else
        handle_error "Failed to restore Borg backup"
    fi
}

perform_manual_restore() {
    local yes_to_all=0
    local confirm_all=0

    local directories=("/etc" "/var" "/opt" "$HOME/.config" "$HOME" "$HOME/.mozilla" "$HOME/.config/google-chrome" "$HOME/.config/microsoft-edge" "$HOME/.local/share/gnome-shell/extensions")
    
    for dir in "${directories[@]}"; do
        local dir_name=$(basename "$dir")
        if [ -d "$restore_dir/$dir_name" ]; then
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to restore $dir?"
                confirm_all=$?
                [ "$confirm_all" -eq 2 ] && yes_to_all=1
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                restore_directory "$restore_dir/$dir_name" "$dir"
            fi
        else
            echo "Backup for $dir not found. Skipping."
        fi
    done

    # Restore package lists
    if [ -f "$restore_dir/rpm_packages.txt" ] || [ -f "$restore_dir/flatpak_packages.txt" ] || [ -f "$restore_dir/pip_packages.txt" ]; then
        if confirm "Do you want to restore installed packages?"; then
            restore_packages "$restore_dir/rpm_packages.txt" "$restore_dir/flatpak_packages.txt" "$restore_dir/pip_packages.txt"
        fi
    fi
}

perform_disk_image_restore() {
    if [ -f "$restore_dir/image/disk-image.img" ]; then
        restore_disk_image "$restore_dir/image/disk-image.img"
    elif [ -f "$restore_dir/image/disk-image.gz" ]; then
        echo "Compressed disk image found. Decompressing..."
        gunzip -c "$restore_dir/image/disk-image.gz" > "$restore_dir/image/disk-image.img"
        restore_disk_image "$restore_dir/image/disk-image.img"
        rm "$restore_dir/image/disk-image.img"
    elif [ -f "$restore_dir/image/disk-image.gz.part-aa" ]; then
        echo "Split compressed disk image found. Reassembling and decompressing..."
        cat "$restore_dir/image/disk-image.gz.part-"* | gunzip -c > "$restore_dir/image/disk-image.img"
        restore_disk_image "$restore_dir/image/disk-image.img"
        rm "$restore_dir/image/disk-image.img"
    elif [ -f "$restore_dir/image/disk-image.part-aa" ]; then
        echo "Split disk image found. Reassembling..."
        cat "$restore_dir/image/disk-image.part-"* > "$restore_dir/image/disk-image.img"
        restore_disk_image "$restore_dir/image/disk-image.img"
        rm "$restore_dir/image/disk-image.img"
    else
        handle_error "No valid disk image found in the backup"
    fi
}

perform_borg_restore() {
    read -p "Enter the path to restore Borg backup: " restore_path
    restore_borg_backup "$restore_dir/borg_repo" "$restore_path"
}

# Main Execution
main() {
    check_and_install_packages

    restore_dir=$(find_latest_backup)
    echo "Found backup directory: $restore_dir"

    # Determine if the backup is encrypted
    if [ -f "$restore_dir.tar.gz.enc" ]; then
        echo "Encrypted backup found. Decrypting..."
        decrypt_backup "$restore_dir.tar.gz.enc" "$restore_dir.tar.gz"
        extract_backup "$restore_dir.tar.gz" "$restore_dir"
        rm "$restore_dir.tar.gz"  # Remove the decrypted archive after extraction
    elif [ -f "$restore_dir.tar.gz" ]; then
        echo "Compressed backup found. Extracting..."
        extract_backup "$restore_dir.tar.gz" "$restore_dir"
    fi

    # Determine the backup type
    if [ -d "$restore_dir/borg_repo" ]; then
        backup_type="borg"
    elif [ -d "$restore_dir/image" ]; then
        backup_type="disk_image"
    else
        backup_type="manual"
    fi

    echo "Detected backup type: $backup_type"

    start_time=$(date +%s)

    case $backup_type in
        "manual") perform_manual_restore ;;
        "disk_image") perform_disk_image_restore ;;
        "borg") perform_borg_restore ;;
        *) handle_error "Invalid backup type" ;;
    esac

    end_time=$(date +%s)
    total_time=$(($end_time - $start_time))

    echo "Restore completed."
    echo "Total time taken: $total_time seconds"
    echo "Detailed report can be found in $restore_dir/restore_report.txt"
    cat "$restore_dir/restore_report.txt"

    echo "Restore process finished. Please reboot your system to ensure all changes take effect."
}

main