#!/bin/bash

# Utility Functions
check_disk_space() {
    local required_space=$1
    local available_space=$(df -k --output=avail "$backup_dir" | tail -n1)
    if [ $available_space -lt $required_space ]; then
        echo "Error: Not enough disk space. Required: $required_space KB, Available: $available_space KB"
        exit 1
    fi
}

handle_error() {
    local error_message=$1
    echo "Error: $error_message" >> "$backup_dir/error.log"
    echo "Error occurred. Check $backup_dir/error.log for details."
    exit 1
}

log_state() {
    echo "$1" >> "$state_file"
}

log_section_report() {
    local section=$1
    local start_time=$2
    local end_time=$3
    echo "$section: completed in $(($end_time - $start_time)) seconds" >> "$backup_dir/backup_report.txt"
}

confirm() {
    while true; do
        read -p "$1 (Y/n/A, default is Y): " yn
        case ${yn:-Y} in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            [Aa]* ) return 2;;
            * ) echo "Please answer yes, no, or all.";;
        esac
    done
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
        read -p "Do you want to install them now? (Y/n): " yn
        case ${yn:-Y} in
            [Yy]* ) 
                if sudo -v; then
                    sudo dnf install -y ${missing_packages[*]}
                else
                    echo "Error: sudo privileges required to install packages. Exiting."
                    exit 1
                fi
                ;;
            [Nn]* ) echo "Required packages are missing. Exiting."; exit 1;;
            * ) echo "Please answer yes or no."; exit 1;;
        esac
    fi
}

# Backup Functions
perform_rsync_backup() {
    local source_dir=$1
    local dest_dir=$2
    rsync -av "$source_dir" "$dest_dir"
}

perform_manual_backup() {
    local yes_to_all=0
    local confirm_all=0

    local directories=("/etc" "/var" "/opt" "$HOME/.config" "$HOME" "$HOME/.mozilla" "$HOME/.config/google-chrome" "$HOME/.config/microsoft-edge" "$HOME/.local/share/gnome-shell/extensions")
    local processed_dirs=()

    for dir in "${directories[@]}"; do
        local dir_name=$(basename "$dir")
        if [[ ! " ${processed_dirs[@]} " =~ " ${dir_name} " ]]; then
            if [ -d "$backup_dir/$dir_name" ]; then
                echo "Backup for $dir already exists. Skipping."
            else
                if [ "$yes_to_all" -eq 0 ]; then
                    confirm "Do you want to back up $dir?"
                    confirm_all=$?
                    [ "$confirm_all" -eq 2 ] && yes_to_all=1
                fi
                if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                    local section_start_time=$(date +%s)
                    if sudo rsync -avh --progress "$dir" "$backup_dir/$dir_name/"; then
                        local section_end_time=$(date +%s)
                        log_section_report "$dir backup" $section_start_time $section_end_time
                        processed_dirs+=("$dir_name")
                    else
                        handle_error "Failed to backup $dir"
                    fi
                fi
            fi
        fi
    done

    # Backup RPM packages
    if confirm "Do you want to backup the list of installed RPM packages?"; then
        local section_start_time=$(date +%s)
        echo "Backing up RPM package list..."
        if rpm -qa > "$backup_dir/rpm_packages.txt"; then
            echo "RPM package list backed up successfully."
            local section_end_time=$(date +%s)
            log_section_report "RPM package list backup" $section_start_time $section_end_time
        else
            handle_error "Failed to backup RPM package list"
        fi
    fi

    # Backup Flatpak packages
    if confirm "Do you want to backup the list of installed Flatpak packages?"; then
        local section_start_time=$(date +%s)
        echo "Backing up Flatpak package list..."
        if flatpak list --app --columns=application > "$backup_dir/flatpak_packages.txt"; then
            echo "Flatpak package list backed up successfully."
            local section_end_time=$(date +%s)
            log_section_report "Flatpak package list backup" $section_start_time $section_end_time
        else
            handle_error "Failed to backup Flatpak package list"
        fi
    fi

    # Backup pip packages
    if confirm "Do you want to backup the list of installed pip packages?"; then
        local section_start_time=$(date +%s)
        echo "Backing up pip package list..."
        if pip list --format=freeze > "$backup_dir/pip_packages.txt"; then
            echo "pip package list backed up successfully."
            local section_end_time=$(date +%s)
            log_section_report "pip package list backup" $section_start_time $section_end_time
        else
            handle_error "Failed to backup pip package list"
        fi
    fi

    # Add other specific backup tasks here (databases, logs, etc.)
}

perform_disk_image_backup() {
    echo "Available disks for imaging:"
    lsblk

    read -p "Enter the disk to image (e.g., /dev/nvme1n1 or /dev/nvme1n1p1): " disk_to_image

    if [ ! -b "$disk_to_image" ]; then
        handle_error "Invalid disk path. Please enter a valid block device."
    fi

    if confirm "Do you want to create a disk image of $disk_to_image?"; then
        local section_start_time=$(date +%s)
        mkdir -p "$backup_dir/image"

        read -p "Compress the disk image? (y/N): " compress_choice
        local compress=$([[ $compress_choice =~ ^[Yy] ]] && echo true || echo false)

        read -p "Split the image into smaller chunks? (y/N): " split_choice
        local split=$([[ $split_choice =~ ^[Yy] ]] && echo true || echo false)
        local split_size="4G"
        $split && read -p "Enter the maximum size for each chunk (e.g., 4G): " split_size

        echo "Using ddrescue for disk imaging..."
        if $compress; then
            if $split; then
                sudo ddrescue -d -f -r3 "$disk_to_image" - | gzip -c | split -b "$split_size" - "$backup_dir/image/disk-image.gz.part-"
            else
                sudo ddrescue -d -f -r3 "$disk_to_image" - | gzip -c > "$backup_dir/image/disk-image.gz"
            fi
        else
            if $split; then
                sudo ddrescue -d -f -r3 "$disk_to_image" - | split -b "$split_size" - "$backup_dir/image/disk-image.part-"
            else
                sudo ddrescue -d -f -r3 "$disk_to_image" "$backup_dir/image/disk-image.img"
            fi
        fi

        if [ $? -eq 0 ]; then
            echo "Disk image created successfully using ddrescue."
            verify_disk_image "$disk_to_image" "$compress" "$split"
        else
            handle_error "Failed to create disk image using ddrescue"
        fi

        local section_end_time=$(date +%s)
        log_section_report "Disk image ($disk_to_image)" $section_start_time $section_end_time
        log_state "disk_image"
    fi
}

verify_disk_image() {
    local disk_to_image=$1
    local compress=$2
    local split=$3

    echo "Verifying the created disk image..."
    if $compress; then
        if $split; then
            cat "$backup_dir/image/disk-image.gz.part-"* | gunzip -c | sudo cmp -n $(sudo blockdev --getsize64 "$disk_to_image") - "$disk_to_image"
        else
            gunzip -c "$backup_dir/image/disk-image.gz" | sudo cmp -n $(sudo blockdev --getsize64 "$disk_to_image") - "$disk_to_image"
        fi
    else
        if $split; then
            cat "$backup_dir/image/disk-image.part-"* | sudo cmp -n $(sudo blockdev --getsize64 "$disk_to_image") - "$disk_to_image"
        else
            sudo cmp -n $(sudo blockdev --getsize64 "$disk_to_image") "$backup_dir/image/disk-image.img" "$disk_to_image"
        fi
    fi
    
    [ $? -eq 0 ] && echo "Disk image verified successfully." || echo "Warning: Disk image verification failed. The image may be corrupted."
}

perform_borg_backup() {
    local borg_repo="$backup_dir/borg_repo"
    if [ ! -d "$borg_repo" ]; then
        echo "Initializing Borg repository..."
        borg init --encryption=repokey "$borg_repo"
    fi

    echo "Creating Borg backup with LZ4 compression..."
    local section_start_time=$(date +%s)

    if borg create --progress --stats --compression lz4 --checkpoint-interval 300 \
        "$borg_repo::backup-{now}" \
        /var/lib/docker \
        "$HOME"; then
        echo "Borg backup created successfully with LZ4 compression."
        local section_end_time=$(date +%s)
        log_section_report "Borg backup with LZ4 compression" $section_start_time $section_end_time
        log_state "borg"
    else
        handle_error "Failed to create Borg backup"
    fi

    echo "Pruning old backups..."
    borg prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6 "$borg_repo"

    if confirm "Do you want to verify the Borg backup?"; then
        echo "Verifying Borg backup..."
        borg check "$borg_repo" && echo "Borg backup verification successful." || echo "Borg backup verification failed. Please check the repository manually."
    fi
}

compress_backup() {
    if [ -z "$compress_done" ] && confirm "Do you want to compress the backup?"; then
        local section_start_time=$(date +%s)
        echo "Compressing the backup..."
        
        if tar -czf "$backup_dir.tar.gz" -C "$backup_dir" .; then
            echo "Backup compressed successfully."
            local section_end_time=$(date +%s)
            log_section_report "Compressing the backup" $section_start_time $section_end_time
            log_state "compress"
        else
            handle_error "Failed to compress the backup"
        fi
    fi
}

encrypt_backup() {
    if [ -z "$encrypt_done" ] && confirm "Do you want to encrypt the backup?"; then
        local section_start_time=$(date +%s)
        echo "Encrypting the backup..."
        
        read -s -p "Enter encryption password: " passphrase
        echo
        read -s -p "Confirm encryption password: " passphrase_confirm
        echo

        if [ "$passphrase" != "$passphrase_confirm" ]; then
            echo "Error: Passwords do not match. Encryption aborted."
            exit 1
        fi
        
        if openssl enc -aes-256-cbc -salt -in "$backup_dir.tar.gz" -out "$backup_dir.tar.gz.enc" -pass pass:"$passphrase"; then
            echo "Backup encrypted successfully."
            echo "IMPORTANT: Remember your encryption password. You will need it to decrypt the backup."
            
            local section_end_time=$(date +%s)
            log_section_report "Encrypting the backup" $section_start_time $section_end_time
            log_state "encrypt"
            
            rm "$backup_dir.tar.gz"
        else
            handle_error "Failed to encrypt the backup"
        fi
    fi
}

verify_backup() {
    if [ "$backup_type" == "3" ]; then
        echo "Verifying Borg backup..."
        borg check "$borg_repo" && echo "Borg backup verification successful." || handle_error "Borg backup verification failed. Please check the repository manually."
    else
        echo "Verifying backup integrity..."
        if [ -f "$backup_dir.tar.gz" ]; then
            local original_file_count=$(find "$backup_dir" -type f | wc -l)
            local archive_file_count=$(tar -tvf "$backup_dir.tar.gz" | wc -l)
            
            if [ "$original_file_count" -eq "$archive_file_count" ]; then
                echo "File count matches. Verifying checksums..."
                if tar -xOf "$backup_dir.tar.gz" | md5sum -c "$backup_dir/checksum.md5"; then
                    echo "Backup verified successfully."
                else
                    handle_error "Backup verification failed: Checksum mismatch."
                fi
            else
                handle_error "Backup verification failed: File count mismatch."
            fi
        elif [ -f "$backup_dir.tar.gz.enc" ]; then
            echo "Backup is encrypted. Decryption required before verification."
        else
            handle_error "Backup archive not found."
        fi
    fi
}

# Main Execution
main() {
    check_and_install_packages

    timestamp=$(date +"%Y%m%d_%H%M%S")
    backup_dir=$(pwd)/backup_$timestamp
    mkdir -p "$backup_dir"

    state_file="$backup_dir/backup_state.log"

    echo "Backup location: $backup_dir"
    check_disk_space 52428800  # Assuming we need at least 50GB

    echo "Choose backup type:"
    echo "1) Manual backup"
    echo "2) Disk image"
    echo "3) Borg backup(Completed/Compressed/Encrypted)"
    read -p "Enter choice [1-3]: " backup_type

    start_time=$(date +%s)

    case $backup_type in
        1) perform_manual_backup ;;
        2) perform_disk_image_backup ;;
        3) perform_borg_backup ;;
        *) echo "Invalid choice. Exiting."; exit 1 ;;
    esac

    if [ "$backup_type" != "3" ]; then
        compress_backup
        encrypt_backup
    fi

    verify_backup

    end_time=$(date +%s)
    total_time=$(($end_time - $start_time))

    echo "Backup completed."
    echo "Total time taken: $total_time seconds"
    echo "Detailed report can be found in $backup_dir/backup_report.txt"
    cat "$backup_dir/backup_report.txt"

    if [ "$backup_type" == "3" ]; then
        echo "Backup process finished. Your Borg backup is stored at $borg_repo"
        echo "Use 'borg list $borg_repo' to see available archives."
    else
        echo "Backup process finished. Your backup is stored at $backup_dir"
        [ -f "$backup_dir.tar.gz.enc" ] && echo "Your encrypted backup is stored at $backup_dir.tar.gz.enc" && echo "Remember to securely store your encryption passphrase!"
    fi
}

main