#!/bin/bash

# Check for required packages and install if missing
required_packages=(rsync dd gzip dnf flatpak pip)
missing_packages=()

for package in "${required_packages[@]}"; do
    if ! command -v $package &> /dev/null; then
        missing_packages+=($package)
    fi
done

if [ ${#missing_packages[@]} -gt 0 ]; then
    echo "The following packages are required for the backup script: ${missing_packages[*]}"
    read -p "Do you want to install them now? (Y/n): " yn
    case $yn in
        [Yy]* | "" ) sudo dnf install -y ${missing_packages[*]};;
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
                config) config_done=1 ;;
                home) home_done=1 ;;
                mozilla) mozilla_done=1 ;;
                chrome) chrome_done=1 ;;
                edge) edge_done=1 ;;
                gnome_extensions) gnome_extensions_done=1 ;;
                packages) packages_done=1 ;;
                pip) pip_done=1 ;;
                disk_image) disk_image_done=1 ;;
                compress) compress_done=1 ;;
            esac
        done < "$state_file"
    fi
}

resume_from_state

echo "Backup location: $backup_dir"

# Function to prompt for user confirmation
confirm() {
    while true; do
        read -p "$1 (Y/n, default is Y): " yn
        case $yn in
            [Yy]* | "" ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
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

    # System configuration files
    if [ -z "$etc_done" ]; then
        if [ -d "$backup_dir/etc" ]; then
            echo "Backup for /etc already exists. Skipping."
        else
            if confirm "Do you want to back up system configuration files (/etc)?"; then
                section_start_time=$(date +%s)
                sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress /etc "$backup_dir/etc/"
                section_end_time=$(date +%s)
                log_section_report "System configuration files (/etc)" $section_start_time $section_end_time
                log_state "etc"
            fi
        fi
    fi

    # User-specific configuration files
    if [ -z "$config_done" ]; then
        if [ -d "$backup_dir/config" ]; then
            echo "Backup for ~/.config already exists. Skipping."
        else
            if confirm "Do you want to back up user-specific configuration files (~/.config)?"; then
                section_start_time=$(date +%s)
                sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress /home/$USER/.config "$backup_dir/config/"
                section_end_time=$(date +%s)
                log_section_report "User-specific configuration files (~/.config)" $section_start_time $section_end_time
                log_state "config"
            fi
        fi
    fi

    # Home directory
    if [ -z "$home_done" ]; then
        if [ -d "$backup_dir/home" ]; then
            echo "Backup for /home/$USER already exists. Skipping."
        else
            if confirm "Do you want to back up the home directory (/home/$USER)?"; then
                section_start_time=$(date +%s)
                sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress /home/$USER "$backup_dir/home/"
                section_end_time=$(date +%s)
                log_section_report "Home directory (/home/$USER)" $section_start_time $section_end_time
                log_state "home"
            fi
        fi
    fi

    # Browser data
    if [ -z "$mozilla_done" ]; then
        if [ -d "$backup_dir/mozilla" ]; then
            echo "Backup for ~/.mozilla already exists. Skipping."
        else
            if confirm "Do you want to back up Firefox data (~/.mozilla)?"; then
                section_start_time=$(date +%s)
                sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress ~/.mozilla "$backup_dir/mozilla/"
                section_end_time=$(date +%s)
                log_section_report "Firefox data (~/.mozilla)" $section_start_time $section_end_time
                log_state "mozilla"
            fi
        fi
    fi

    if [ -z "$chrome_done" ]; then
        if [ -d "$backup_dir/google-chrome" ]; then
            echo "Backup for ~/.config/google-chrome already exists. Skipping."
        else
            if confirm "Do you want to back up Chrome data (~/.config/google-chrome)?"; then
                section_start_time=$(date +%s)
                sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress ~/.config/google-chrome "$backup_dir/google-chrome/"
                section_end_time=$(date +%s)
                log_section_report "Chrome data (~/.config/google-chrome)" $section_start_time $section_end_time
                log_state "chrome"
            fi
        fi
    fi

    if [ -z "$edge_done" ]; then
        if [ -d "$backup_dir/microsoft-edge" ]; then
            echo "Backup for ~/.config/microsoft-edge already exists. Skipping."
        else
            if confirm "Do you want to back up Edge data (~/.config/microsoft-edge)?"; then
                section_start_time=$(date +%s)
                sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress ~/.config/microsoft-edge "$backup_dir/microsoft-edge/"
                section_end_time=$(date +%s)
                log_section_report "Edge data (~/.config/microsoft-edge)" $section_start_time $section_end_time
                log_state "edge"
            fi
        fi
    fi

    # GNOME extensions
    if [ -z "$gnome_extensions_done" ]; then
        if [ -d "$backup_dir/gnome-extensions" ]; then
            echo "Backup for GNOME extensions already exists. Skipping."
        else
            if confirm "Do you want to back up GNOME extensions (~/.local/share/gnome-shell/extensions)?"; then
                section_start_time=$(date +%s)
                sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress ~/.local/share/gnome-shell/extensions "$backup_dir/gnome-extensions/"
                sudo rsync -avh --partial --partial-dir="$backup_dir/partial" --progress /usr/share/gnome-shell/extensions "$backup_dir/gnome-extensions/system"
                section_end_time=$(date +%s)
                log_section_report "GNOME extensions (~/.local/share/gnome-shell/extensions and /usr/share/gnome-shell/extensions)" $section_start_time $section_end_time
                log_state "gnome_extensions"
            fi
        fi
    fi

    # Installed packages list
    if [ -z "$packages_done" ]; then
        if [ -f "$backup_dir/rpm-packages-list.txt" ]; then
            echo "Backup for installed packages list already exists. Skipping."
        else
            if confirm "Do you want to back up the list of installed packages?"; then
                section_start_time=$(date +%s)
                sudo dnf list installed > "$backup_dir/rpm-packages-list.txt"
                flatpak list --app > "$backup_dir/flatpak-apps-list.txt"
                section_end_time=$(date +%s)
                log_section_report "Installed packages list" $section_start_time $section_end_time
                log_state "packages"
            fi
        fi
    fi

    # pip packages
    if [ -z "$pip_done" ]; then
        if [ -f "$backup_dir/requirements.txt" ]; then
            echo "Backup for pip packages already exists. Skipping."
        else
            if confirm "Do you want to back up pip packages?"; then
                section_start_time=$(date +%s)
                pip freeze > "$backup_dir/requirements.txt"
                section_end_time=$(date +%s)
                log_section_report "pip packages" $section_start_time $section_end_time
                log_state "pip"
            fi
        fi
    fi

else
    # Disk image backup
    if [ -z "$disk_image_done" ]; then
        echo "Available disks for imaging:"
        lsblk

        read -p "Enter the disk to image (e.g., /dev/nvme1n1 or a specific partition like /dev/nvme1n1p1): " disk_to_image

        if confirm "Do you want to create a disk image of $disk_to_image?"; then
            section_start_time=$(date +%s)
            mkdir -p "$backup_dir/image"
            sudo dd if=$disk_to_image of="$backup_dir/image/disk-image.img" bs=4M status=progress
            section_end_time=$(date +%s)
            log_section_report "Disk image ($disk_to_image)" $section_start_time $section_end_time
            log_state "disk_image"
        fi
    fi
fi

# Compress the backup
if [ -z "$compress_done" ]; then
    if confirm "Do you want to compress the backup?"; then
        section_start_time=$(date +%s)
        tar -czvf "$backup_dir/backup.tar.gz" -C "$backup_dir" .
        section_end_time=$(date +%s)
        log_section_report "Compressing the backup" $section_start_time $section_end_time
        log_state "compress"
    fi
fi

end_time=$(date +%s)
total_time=$(($end_time - $start_time))

# Summary report
echo "Backup completed."
echo "Total time taken: $total_time seconds"
echo "Detailed report can be found in $backup_dir/backup_report.txt"
cat "$backup_dir/backup_report.txt"
