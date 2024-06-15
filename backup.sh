#!/bin/bash

# Get the directory from which the script is executed
backup_dir=$(pwd)

echo "Backup location: $backup_dir"

# Function to prompt for user confirmation
confirm() {
    while true; do
        read -p "$1 (Y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# System configuration files
if confirm "Do you want to back up system configuration files (/etc)?"; then
    sudo rsync -avh --progress /etc "$backup_dir/etc/"
fi

# User-specific configuration files
if confirm "Do you want to back up user-specific configuration files (~/.config)?"; then
    sudo rsync -avh --progress /home/$USER/.config "$backup_dir/config/"
    sudo rsync -avh --progress /home/$USER/.* "$backup_dir/dotfiles/"
fi

# Home directory
if confirm "Do you want to back up the home directory (/home/$USER)?"; then
    sudo rsync -avh --progress /home/$USER "$backup_dir/home/"
fi

# Browser data
if confirm "Do you want to back up Firefox data (~/.mozilla)?"; then
    sudo rsync -avh --progress ~/.mozilla "$backup_dir/mozilla/"
fi

if confirm "Do you want to back up Chrome data (~/.config/google-chrome)?"; then
    sudo rsync -avh --progress ~/.config/google-chrome "$backup_dir/google-chrome/"
fi

if confirm "Do you want to back up Chromium data (~/.config/chromium)?"; then
    sudo rsync -avh --progress ~/.config/chromium "$backup_dir/chromium/"
fi

# GNOME extensions
if confirm "Do you want to back up GNOME extensions (~/.local/share/gnome-shell/extensions)?"; then
    sudo rsync -avh --progress ~/.local/share/gnome-shell/extensions "$backup_dir/gnome-extensions/"
    sudo rsync -avh --progress /usr/share/gnome-shell/extensions "$backup_dir/gnome-extensions/system"
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

# Disk image
if confirm "Do you want to create a disk image of the main drive?"; then
    sudo dd if=/dev/nvme1n1 of="$backup_dir/disk-image.img" bs=4M status=progress
fi

echo "Backup completed."
