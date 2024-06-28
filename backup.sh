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

# Function to handle errors
handle_error() {
    local error_message=$1
    echo "Error: $error_message" >> "$backup_dir/error.log"
    echo "Error occurred. Check $backup_dir/error.log for details."
}

# Function to verify backup integrity
verify_backup() {
    echo "Verifying backup integrity..."
    if tar -tvf "$backup_dir/backup.tar.gz" > /dev/null 2>&1; then
        echo "Backup verified successfully."
    else
        echo "Error: Backup verification failed."
    fi
}

# Check for required packages and install if missing
required_packages=(rsync dd gzip dnf flatpak pip openssl)
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

# Get the directory from which the script is executed
timestamp=$(date +"%Y%m%d_%H%M%S")
backup_dir=$(pwd)/backup_$timestamp
mkdir -p "$backup_dir"

state_file="$backup_dir/backup_state.log"

trap "echo 'Backup interrupted'; exit 1" SIGINT SIGTERM

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
                compress) compress_done=1 ;;
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
read -p "Enter choice [1-2]: " backup_type

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

    # Backup /var
    if [ -z "$var_done" ]; then
        if [ -d "$backup_dir/var" ]; then
            echo "Backup for /var already exists. Skipping."
        else
            if [ "$yes_to_all" -eq 0 ]; then
                confirm "Do you want to back up /var?"
                confirm_all=$?
                if [ "$confirm_all" -eq 2 ]; then
                    yes_to_all=1
                fi
            fi
            if [ "$yes_to_all" -eq 1 ] || [ "$confirm_all" -eq 0 ]; then
                section_start_time=$(date +%s)
                if sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress /var "$backup_dir/var/"; then
                    section_end_time=$(date +%s)
                    log_section_report "Var directory (/var)" $section_start_time $section_end_time
                    log_state "var"
                else
                    handle_error "Failed to backup /var"
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

else
    # Disk image backup
    if [ -z "$disk_image_done" ]; then
        echo "Available disks for imaging:"
        lsblk

        read -p "Enter the disk to image (e.g., /dev/nvme1n1 or a specific partition like /dev/nvme1n1p1): " disk_to_image

        # Validate the entered disk path
        if [ ! -b "$disk_to_image" ]; then
            echo "Error: Invalid disk path. Please enter a valid block device."
            exit 1
        fi

        if confirm "Do you want to create a disk image of $disk_to_image?"; then
            section_start_time=$(date +%s)
            mkdir -p "$backup_dir/image"
            if sudo dd if=$disk_to_image of="$backup_dir/image/disk-image.img" bs=4M status=progress; then
                section_end_time=$(date +%s)
                log_section_report "Disk image ($disk_to_image)" $section_start_time $section_end_time
                log_state "disk_image"
            else
                handle_error "Failed to create disk image"
            fi
        fi
    fi
fi

# Compress and encrypt the backup
if [ -z "$compress_done" ]; then
    if confirm "Do you want to compress and encrypt the backup?"; then
        section_start_time=$(date +%s)
        echo "Compressing and encrypting the backup..."
        
        # Generate a random passphrase
        passphrase=$(openssl rand -base64 32)
        
        # Compress and encrypt in one step
        if tar -czf - -C "$backup_dir" . | openssl enc -aes-256-cbc -salt -out "$backup_dir.tar.gz.enc" -pass pass:"$passphrase"; then
            echo "Backup compressed and encrypted successfully."
            echo "Your encryption passphrase is: $passphrase"
            echo "IMPORTANT: Store this passphrase securely. You will need it to decrypt the backup."
            
            # Save the passphrase to a file (consider a more secure method in production)
            echo "$passphrase" > "$backup_dir.passphrase"
            chmod 600 "$backup_dir.passphrase"
            
            section_end_time=$(date +%s)
            log_section_report "Compressing and encrypting the backup" $section_start_time $section_end_time
            log_state "compress"
        else
            handle_error "Failed to compress and encrypt the backup"
        fi
    fi
fi

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

echo "Backup process finished. Your encrypted backup is stored at $backup_dir.tar.gz.enc"
echo "Remember to securely store your encryption passphrase!"
