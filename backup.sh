#!/bin/bash

# Function to check available disk space
check_disk_space() {
    local required_space=$1
    local available_space=$(df -k --output=avail "$backup_dir" | tail -n1)
    if [ $available_space -lt $required_space ]; then
        echo "Error: Not enough disk space. Required: $required_space KB, Available: $available_space KB"
        exit 1
    fi
}

# Improved error handling function with cleanup
handle_error() {
    local error_message=$1
    echo "Error: $error_message" >> "$backup_dir/error.log"
    echo "Error occurred. Check $backup_dir/error.log for details."
    cleanup
    exit 1
}

# Cleanup function for failed or interrupted backups
cleanup() {
    echo "Cleaning up partial or failed backup..."
    if [ -d "$backup_dir" ]; then
        rm -rf "$backup_dir"
    fi
    if [ -f "$backup_dir.tar.gz" ]; then
        rm "$backup_dir.tar.gz"
    fi
    if [ -f "$backup_dir.tar.gz.enc" ]; then
        rm "$backup_dir.tar.gz.enc"
    fi
    echo "Cleanup completed."
}

# Function to verify backup integrity
verify_backup() {
    if [ "$backup_type" == "3" ]; then
        echo "Verifying Borg backup..."
        if borg check "$borg_repo"; then
            echo "Borg backup verification successful."
        else
            handle_error "Borg backup verification failed. Please check the repository manually."
        fi
    else
        echo "Verifying backup integrity..."
        if [ -f "$backup_dir.tar.gz" ]; then
            # Improved verification: Check file count and perform checksum
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

# Function for incremental backups
perform_incremental_backup() {
    local source_dir=$1
    local dest_dir=$2
    local snapshot_dir="$backup_dir/snapshots"

    # Create snapshot directory if it doesn't exist
    mkdir -p "$snapshot_dir"

    # Find the most recent snapshot
    local latest_snapshot=$(ls -t "$snapshot_dir" | head -n1)

    if [ -n "$latest_snapshot" ]; then
        # Perform incremental backup
        rsync -av --delete --link-dest="$snapshot_dir/$latest_snapshot" "$source_dir" "$dest_dir"
    else
        # Perform full backup if no previous snapshot exists
        rsync -av "$source_dir" "$dest_dir"
    fi

    # Create a new snapshot
    cp -al "$dest_dir" "$snapshot_dir/$(date +%Y%m%d_%H%M%S)"
}


# Check for required packages and install if missing
required_packages=(rsync dd gzip dnf flatpak pip openssl borg ddrescue cmp)
missing_packages=()

for package in "${required_packages[@]}"; do
    if ! command -v $package &> /dev/null; then
        missing_packages+=($package)
    fi
done

if [ ${#missing_packages[@]} -gt 0 ]; then
    echo "The following packages are required for the backup script: ${missing_packages[*]}"
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


# Check for incomplete backups
incomplete_backups=$(find . -maxdepth 1 -type d -name "backup_*" -exec test -f {}/backup_state.log \; -print)
if [ -n "$incomplete_backups" ]; then
    echo "Incomplete backups found:"
    select backup_dir in $incomplete_backups; do
        if [ -n "$backup_dir" ]; then
            echo "Resuming backup in $backup_dir"
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done
else
    # Create new backup directory
    timestamp=$(date +"%Y%m%d_%H%M%S")
    backup_dir=$(pwd)/backup_$timestamp
    mkdir -p "$backup_dir"
fi

state_file="$backup_dir/backup_state.log"

trap cleanup SIGINT SIGTERM

log_state() {
    echo "$1" >> "$state_file"
}

resume_from_state() {
    if [ -f "$state_file" ]; then
        while read -r state; do
            case $state in
                etc) etc_done=1 ;;
                var) var_done=1 ;;
                opt) opt_done=1 ;;
                config) config_done=1 ;;
                home) home_done=1 ;;
                mozilla) mozilla_done=1 ;;
                chrome) chrome_done=1 ;;
                edge) edge_done=1 ;;
                gnome_extensions) gnome_extensions_done=1 ;;
                packages) packages_done=1 ;;
                pip) pip_done=1 ;;
                databases) databases_done=1 ;;
                logs) logs_done=1 ;;
                disk_image) disk_image_done=1 ;;
                borg) borg_done=1 ;;
                compress) compress_done=1 ;;
                encrypt) encrypt_done=1 ;;
            esac
        done < "$state_file"
    fi
}

resume_from_state

echo "Backup location: $backup_dir"

# Check for available disk space (assuming we need at least 50GB)
check_disk_space 52428800

# Function to prompt for user confirmation
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

# Function to log section reports
log_section_report() {
    section=$1
    start_time=$2
    end_time=$3
    echo "$section: completed in $(($end_time - $start_time)) seconds" >> "$backup_dir/backup_report.txt"
}

# Prompt user for backup type
echo "Choose backup type:"
echo "1) Manual backup"
echo "2) Disk image"
echo "3) Borg backup(Completed/Compressed/Encrypted)"
read -p "Enter choice [1-3]: " backup_type

start_time=$(date +%s)

if [ "$backup_type" == "1" ]; then
    # Manual backup
    yes_to_all=0
    confirm_all=0

    # System configuration files
    if [ -z "$etc_done" ]; then
        if [ -d "$backup_dir/etc" ]; then
            echo "Backup for /etc already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up system configuration files (/etc)?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                if sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress /etc "$backup_dir/etc/"; then
                    section_end_time=$(date +%s)
                    log_section_report "System configuration files (/etc)" $section_start_time $section_end_time
                    log_state "etc"
                else
                    handle_error "Failed to backup /etc"
                fi
            fi
        fi
    fi

    # Backup /var/lib
    if [ -z "$var_lib_done" ]; then
        if [ -d "$backup_dir/var_lib" ]; then
            echo "Backup for /var/lib already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up /var/lib?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                if sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress /var/lib "$backup_dir/var_lib/"; then
                    section_end_time=$(date +%s)
                    log_section_report "Var lib directory (/var/lib)" $section_start_time $section_end_time
                    log_state "var_lib"
                else
                    handle_error "Failed to backup /var/lib"
                fi
            fi
        fi
    fi

    # Backup /opt
    if [ -z "$opt_done" ]; then
        if [ -d "$backup_dir/opt" ]; then
            echo "Backup for /opt already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up /opt?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                if sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress /opt "$backup_dir/opt/"; then
                    section_end_time=$(date +%s)
                    log_section_report "Opt directory (/opt)" $section_start_time $section_end_time
                    log_state "opt"
                else
                    handle_error "Failed to backup /opt"
                fi
            fi
        fi
    fi

    # User-specific configuration files
    if [ -z "$config_done" ]; then
        if [ -d "$backup_dir/config" ]; then
            echo "Backup for ~/.config already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up user-specific configuration files (~/.config)?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                if rsync -avh --partial --partial-dir="$backup_dir/partial" --progress "$HOME/.config" "$backup_dir/config/"; then
                    section_end_time=$(date +%s)
                    log_section_report "User-specific configuration files (~/.config)" $section_start_time $section_end_time
                    log_state "config"
                else
                    handle_error "Failed to backup ~/.config"
                fi
            fi
        fi
    fi

    # Home directory
    if [ -z "$home_done" ]; then
        if [ -d "$backup_dir/home" ]; then
            echo "Backup for $HOME already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up the home directory ($HOME)?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                if rsync -avh --partial --partial-dir="$backup_dir/partial" --progress "$HOME" "$backup_dir/home/"; then
                    section_end_time=$(date +%s)
                    log_section_report "Home directory ($HOME)" $section_start_time $section_end_time
                    log_state "home"
                else
                    handle_error "Failed to backup $HOME"
                fi
            fi
        fi
    fi

    # Browser data
    if [ -z "$mozilla_done" ]; then
        if [ -d "$backup_dir/mozilla" ]; then
            echo "Backup for ~/.mozilla already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up Firefox data (~/.mozilla)?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                if rsync -avh --partial --partial-dir="$backup_dir/partial" --progress "$HOME/.mozilla" "$backup_dir/mozilla/"; then
                    section_end_time=$(date +%s)
                    log_section_report "Firefox data (~/.mozilla)" $section_start_time $section_end_time
                    log_state "mozilla"
                else
                    handle_error "Failed to backup Firefox data"
                fi
            fi
        fi
    fi

    if [ -z "$chrome_done" ]; then
        if [ -d "$backup_dir/google-chrome" ]; then
            echo "Backup for ~/.config/google-chrome already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up Chrome data (~/.config/google-chrome)?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                if rsync -avh --partial --partial-dir="$backup_dir/partial" --progress "$HOME/.config/google-chrome" "$backup_dir/google-chrome/"; then
                    section_end_time=$(date +%s)
                    log_section_report "Chrome data (~/.config/google-chrome)" $section_start_time $section_end_time
                    log_state "chrome"
                else
                    handle_error "Failed to backup Chrome data"
                fi
            fi
        fi
    fi

    if [ -z "$edge_done" ]; then
        if [ -d "$backup_dir/microsoft-edge" ]; then
            echo "Backup for ~/.config/microsoft-edge already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up Edge data (~/.config/microsoft-edge)?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                if rsync -avh --partial --partial-dir="$backup_dir/partial" --progress "$HOME/.config/microsoft-edge" "$backup_dir/microsoft-edge/"; then
                    section_end_time=$(date +%s)
                    log_section_report "Edge data (~/.config/microsoft-edge)" $section_start_time $section_end_time
                    log_state "edge"
                else
                    handle_error "Failed to backup Edge data"
                fi
            fi
        fi
    fi

    # GNOME extensions
    if [ -z "$gnome_extensions_done" ]; then
        if [ -d "$backup_dir/gnome-extensions" ]; then
            echo "Backup for GNOME extensions already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up GNOME extensions (~/.local/share/gnome-shell/extensions)?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                if rsync -avh --partial --partial-dir="$backup_dir/partial" --progress "$HOME/.local/share/gnome-shell/extensions" "$backup_dir/gnome-extensions/" && \
                   sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress /usr/share/gnome-shell/extensions "$backup_dir/gnome-extensions/system"; then
                    section_end_time=$(date +%s)
                    log_section_report "GNOME extensions (~/.local/share/gnome-shell/extensions and /usr/share/gnome-shell/extensions)" $section_start_time $section_end_time
                    log_state "gnome_extensions"
                else
                    handle_error "Failed to backup GNOME extensions"
                fi
            fi
        fi
    fi

# Installed packages list
    if [ -z "$packages_done" ]; then
        if [ -f "$backup_dir/rpm-packages-list.txt" ]; then
            echo "Backup for installed packages list already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up the list of installed packages?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                if dnf list installed > "$backup_dir/rpm-packages-list.txt" && \
                   flatpak list --app > "$backup_dir/flatpak-apps-list.txt"; then
                    section_end_time=$(date +%s)
                    log_section_report "Installed packages list" $section_start_time $section_end_time
                    log_state "packages"
                else
                    handle_error "Failed to backup installed packages list"
                fi
            fi
        fi
    fi

    # pip packages
    if [ -z "$pip_done" ]; then
        if [ -f "$backup_dir/requirements.txt" ]; then
            echo "Backup for pip packages already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up pip packages?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                if pip freeze > "$backup_dir/requirements.txt"; then
                    section_end_time=$(date +%s)
                    log_section_report "pip packages" $section_start_time $section_end_time
                    log_state "pip"
                else
                    handle_error "Failed to backup pip packages"
                fi
            fi
        fi
    fi

    # Database dumps
    if [ -z "$databases_done" ]; then
        if [ -d "$backup_dir/database_dumps" ]; then
            echo "Backup for database dumps already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up database dumps?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                mkdir -p "$backup_dir/database_dumps"
                
                # MySQL/MariaDB
                if command -v mysqldump &> /dev/null; then
                    if sudo mysqldump --all-databases > "$backup_dir/database_dumps/mysql_dump.sql"; then
                        echo "MySQL/MariaDB dump created successfully."
                    else
                        handle_error "Failed to create MySQL/MariaDB dump"
                    fi
                fi
                
                # PostgreSQL
                if command -v pg_dumpall &> /dev/null; then
                    if sudo -u postgres pg_dumpall > "$backup_dir/database_dumps/postgresql_dump.sql"; then
                        echo "PostgreSQL dump created successfully."
                    else
                        handle_error "Failed to create PostgreSQL dump"
                    fi
                fi
                
                section_end_time=$(date +%s)
                log_section_report "Database dumps" $section_start_time $section_end_time
                log_state "databases"
            fi
        fi
    fi

    # System logs
    if [ -z "$logs_done" ]; then
        if [ -d "$backup_dir/system_logs" ]; then
            echo "Backup for system logs already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up system logs?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                if sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress /var/log "$backup_dir/system_logs/"; then
                    section_end_time=$(date +%s)
                    log_section_report "System logs" $section_start_time $section_end_time
                    log_state "logs"
                else
                    handle_error "Failed to backup system logs"
                fi
            fi
        fi
    fi

elif [ "$backup_type" == "2" ]; then
    # Improved disk image backup function
    perform_disk_image_backup() {
    echo "Available disks for imaging:"
    lsblk

    read -p "Enter the disk to image (e.g., /dev/nvme1n1 or a specific partition like /dev/nvme1n1p1): " disk_to_image

    # Validate the entered disk path
    if [ ! -b "$disk_to_image" ]; then
        handle_error "Invalid disk path. Please enter a valid block device."
    fi

    if confirm "Do you want to create a disk image of $disk_to_image?"; then
        section_start_time=$(date +%s)
        mkdir -p "$backup_dir/image"

        # Compression option
        compress=false
        read -p "Do you want to compress the disk image? This will save space but take longer. (y/N): " compress_choice
        case $compress_choice in
            [Yy]* ) compress=true;;
            * ) compress=false;;
        esac

        # Splitting option
        split=false
        split_size="4G"
        read -p "Do you want to split the image into smaller chunks? This is useful for large disks or FAT32 storage. (y/N): " split_choice
        case $split_choice in
            [Yy]* ) 
                split=true
                read -p "Enter the maximum size for each chunk (e.g., 4G for 4 gigabytes): " split_size
                ;;
            * ) split=false;;
        esac

        # Use ddrescue for better error handling and progress reporting
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
            
            # Verification step
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
            
            if [ $? -eq 0 ]; then
                echo "Disk image verified successfully."
            else
                echo "Warning: Disk image verification failed. The image may be corrupted."
            fi
        else
            handle_error "Failed to create disk image using ddrescue"
        fi

        section_end_time=$(date +%s)
        log_section_report "Disk image ($disk_to_image)" $section_start_time $section_end_time
        log_state "disk_image"
    fi
}

elif [ "$backup_type" == "3" ]; then
    # Borg backup
    if [ -z "$borg_done" ]; then
        # Initialize Borg repository if it doesn't exist
        borg_repo="$backup_dir/borg_repo"
        if [ ! -d "$borg_repo" ]; then
            echo "Initializing Borg repository..."
            borg init --encryption=repokey "$borg_repo"
        fi

        # Create Borg backup with LZ4 compression
        echo "Creating Borg backup with LZ4 compression..."
        section_start_time=$(date +%s)

        if borg create --progress --stats --compression lz4 --checkpoint-interval 300 \
            "$borg_repo::backup-{now}" \
            /var/lib/docker \
            "$HOME"; then
            echo "Borg backup created successfully with LZ4 compression."
            section_end_time=$(date +%s)
            log_section_report "Borg backup with LZ4 compression" $section_start_time $section_end_time
            log_state "borg"
        else
            handle_error "Failed to create Borg backup"
        fi

        # Prune old backups
        echo "Pruning old backups..."
        borg prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6 "$borg_repo"

        # Ask user if they want to verify the backup
        if confirm "Do you want to verify the Borg backup?"; then
            echo "Verifying Borg backup..."
            if borg check "$borg_repo"; then
                echo "Borg backup verification successful."
            else
                echo "Borg backup verification failed. Please check the repository manually."
            fi
        fi
    fi
else
    echo "Invalid choice. Exiting."
    exit 1
fi

# Remove compression and encryption steps for Borg backup
if [ "$backup_type" != "3" ]; then
    # Compress the backup
    if [ -z "$compress_done" ]; then
        if confirm "Do you want to compress the backup?"; then
            section_start_time=$(date +%s)
            echo "Compressing the backup..."
            
            if tar -czf "$backup_dir.tar.gz" -C "$backup_dir" .; then
                echo "Backup compressed successfully."
                section_end_time=$(date +%s)
                log_section_report "Compressing the backup" $section_start_time $section_end_time
                log_state "compress"
            else
                handle_error "Failed to compress the backup"
            fi
        fi
    fi

    # Encrypt the backup
    if [ -z "$encrypt_done" ]; then
        if confirm "Do you want to encrypt the backup?"; then
            section_start_time=$(date +%s)
            echo "Encrypting the backup..."
            
            # Prompt for password
            read -s -p "Enter encryption password: " passphrase
            echo
            read -s -p "Confirm encryption password: " passphrase_confirm
            echo

            # Verify passwords match
            if [ "$passphrase" != "$passphrase_confirm" ]; then
                echo "Error: Passwords do not match. Encryption aborted."
                exit 1
            fi
            
            # Encrypt the compressed backup
            if openssl enc -aes-256-cbc -salt -in "$backup_dir.tar.gz" -out "$backup_dir.tar.gz.enc" -pass pass:"$passphrase"; then
                echo "Backup encrypted successfully."
                echo "IMPORTANT: Remember your encryption password. You will need it to decrypt the backup."
                
                section_end_time=$(date +%s)
                log_section_report "Encrypting the backup" $section_start_time $section_end_time
                log_state "encrypt"
                
                # Remove the unencrypted compressed file
                rm "$backup_dir.tar.gz"
            else
                handle_error "Failed to encrypt the backup"
            fi
        fi
    fi
fi

# Modified verify_backup function
verify_backup() {
    if [ "$backup_type" == "3" ]; then
        echo "Borg backup does not require additional verification."
    else
        echo "Verifying backup integrity..."
        if tar -tvf "$backup_dir/backup.tar.gz" > /dev/null 2>&1; then
            echo "Backup verified successfully."
        else
            echo "Error: Backup verification failed."
        fi
    fi
}

# Main backup process
case $backup_type in
    1) 
        # Manual backup with incremental option
        for dir in /etc /var/lib /opt "$HOME/.config" "$HOME"; do
            perform_incremental_backup "$dir" "$backup_dir/$(basename "$dir")"
        done
        ;;
    2) perform_disk_image_backup ;;
    3) borg_backup ;;
    *) handle_error "Invalid choice. Exiting." ;;
esac

verify_backup

end_time=$(date +%s)
total_time=$(($end_time - $start_time))

# Summary report
echo "Backup completed."
echo "Total time taken: $total_time seconds"
echo "Detailed report can be found in $backup_dir/backup_report.txt"
cat "$backup_dir/backup_report.txt"

# Clean up temporary files and directories
rm -rf "$backup_dir/partial"

if [ "$backup_type" == "3" ]; then
    echo "Backup process finished. Your Borg backup is stored at $borg_repo"
    echo "Use 'borg list $borg_repo' to see available archives."
else
    echo "Backup process finished. Your backup is stored at $backup_dir"
    if [ -f "$backup_dir.tar.gz.enc" ]; then
        echo "Your encrypted backup is stored at $backup_dir.tar.gz.enc"
        echo "Remember to securely store your encryption passphrase!"
    fi
fi