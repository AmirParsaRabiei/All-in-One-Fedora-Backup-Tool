#!/bin/bash

# Get the directory from which the script is executed
backup_dir=$(pwd)
start_time=$(date +%s)

echo "Backup location: $backup_dir"

# List of required packages
required_packages=("rsync" "pv" "dnf" "flatpak" "pip" "dd" "gzip")

# Function to check if a package is installed
is_installed() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install missing packages
install_packages() {
    sudo dnf install -y "$@"
}

# Check for required packages
missing_packages=()
for pkg in "${required_packages[@]}"; do
    if ! is_installed "$pkg"; then
        missing_packages+=("$pkg")
    fi
done

# Prompt to install missing packages
if [ ${#missing_packages[@]} -ne 0 ]; then
    echo "The following packages are required but not installed: ${missing_packages[*]}"
    read -p "Do you want to install these packages now? (Y/n, default is Y): " yn
    case $yn in
        [Yy]* | "" )
            echo "Installing packages..."
            install_packages "${missing_packages[@]}"
            ;;
        [Nn]* )
            echo "Backup cannot proceed without the required packages. Exiting."
            exit 1
            ;;
        * )
            echo "Invalid response. Exiting."
            exit 1
            ;;
    esac
fi

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

# Function to show progress with rsync
rsync_progress() {
    source=$1
    dest=$2
    rsync -avh --progress "$source" "$dest" | pv -lep -s $(rsync --stats "$source" "$dest" | awk '/Total transferred file size:/ {print $5$6}' | numfmt --from=iec --to=none)
}

# System configuration files
if confirm "Do you want to back up system configuration files (/etc)?"; then
    sudo rsync_progress /etc "$backup_dir/etc/"
fi

# User-specific configuration files
if confirm "Do you want to back up user-specific configuration files (~/.config)?"; then
    sudo rsync_progress /home/$USER/.config "$backup_dir/config/"
    sudo rsync_progress /home/$USER/.* "$backup_dir/dotfiles/"
fi

# Home directory
if confirm "Do you want to back up the home directory (/home/$USER)?"; then
    sudo rsync_progress /home/$USER "$backup_dir/home/"
fi

# Browser data
if confirm "Do you want to back up Firefox data (~/.mozilla)?"; then
    sudo rsync_progress ~/.mozilla "$backup_dir/mozilla/"
fi

if confirm "Do you want to back up Chrome data (~/.config/google-chrome)?"; then
    sudo rsync_progress ~/.config/google-chrome "$backup_dir/google-chrome/"
fi

if confirm "Do you want to back up Chromium data (~/.config/chromium)?"; then
    sudo rsync_progress ~/.config/chromium "$backup_dir/chromium/"
fi

# GNOME extensions
if confirm "Do you want to back up GNOME extensions (~/.local/share/gnome-shell/extensions)?"; then
    sudo rsync_progress ~/.local/share/gnome-shell/extensions "$backup_dir/gnome-extensions/"
    sudo rsync_progress /usr/share/gnome-shell/extensions "$backup_dir/gnome-extensions/system"
fi

# Installed packages list
if confirm "Do you want to back up the list of installed packages?"; then
    sudo dnf list installed > "$backup_dir/rpm-packages-list.txt"
    flatpak list --app > "$backup_dir/flatpak-apps-list.txt"
fi

# pip packages
if confirm "Do you want to back up pip packages?"; then
    pip freeze > "$backup_dir/requirements.txt"
fi

# SSH keys
if confirm "Do you want to back up SSH keys (~/.ssh)?"; then
    sudo rsync_progress ~/.ssh "$backup_dir/ssh/"
fi

# Cron jobs
if confirm "Do you want to back up cron jobs?"; then
    sudo crontab -l > "$backup_dir/root-crontab"
    crontab -l > "$backup_dir/user-crontab"
fi

# Docker containers and images
if confirm "Do you want to back up Docker containers and images?"; then
    sudo docker ps -a > "$backup_dir/docker-containers.txt"
    sudo docker images > "$backup_dir/docker-images.txt"
    sudo docker save $(sudo docker images -q) -o "$backup_dir/docker-images.tar"
fi

# Database backups (example for MySQL)
if confirm "Do you want to back up MySQL databases?"; then
    sudo mysqldump --all-databases > "$backup_dir/all-databases.sql"
fi

# Custom applications
if confirm "Do you want to back up custom applications (/opt and /usr/local)?"; then
    sudo rsync_progress /opt "$backup_dir/opt/"
    sudo rsync_progress /usr/local "$backup_dir/usr-local/"
fi

# Disk image
if confirm "Do you want to create a disk image of the main drive?"; then
    sudo dd if=/dev/nvme1n1 | pv | sudo dd of="$backup_dir/disk-image.img" bs=4M
fi

# Compress the backup directory
if confirm "Do you want to compress the backup directory?"; then
    tar -czvf "$backup_dir/backup-$(date +%F).tar.gz" -C "$backup_dir" .
fi

end_time=$(date +%s)
elapsed_time=$(( end_time - start_time ))

# Summary report
echo -e "\nBackup completed."
echo "Total time taken: $((elapsed_time / 60)) minutes and $((elapsed_time % 60)) seconds."
du -sh "$backup_dir" | awk '{print "Total backup size: " $1}'
