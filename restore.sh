#!/bin/bash

# Get the backup directory
read -p "Enter the backup directory to restore from: " backup_dir

if [ ! -d "$backup_dir" ]; then
    echo "Backup directory not found!"
    exit 1
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

# Restore system configuration files
if [ -d "$backup_dir/etc" ]; then
    if confirm "Do you want to restore system configuration files (/etc)?"; then
        sudo rsync -avh --progress "$backup_dir/etc/" /etc
    fi
fi

# Restore user-specific configuration files
if [ -d "$backup_dir/config" ]; then
    if confirm "Do you want to restore user-specific configuration files (~/.config)?"; then
        rsync -avh --progress "$backup_dir/config/" /home/$USER/.config
    fi
fi

# Restore home directory
if [ -d "$backup_dir/home" ]; then
    if confirm "Do you want to restore the home directory (/home/$USER)?"; then
        rsync -avh --progress "$backup_dir/home/" /home/$USER
    fi
fi

# Restore Firefox data
if [ -d "$backup_dir/mozilla" ]; then
    if confirm "Do you want to restore Firefox data (~/.mozilla)?"; then
        rsync -avh --progress "$backup_dir/mozilla/" ~/.mozilla
    fi
fi

# Restore Chrome data
if [ -d "$backup_dir/google-chrome" ]; then
    if confirm "Do you want to restore Chrome data (~/.config/google-chrome)?"; then
        rsync -avh --progress "$backup_dir/google-chrome/" ~/.config/google-chrome
    fi
fi

# Restore Edge data
if [ -d "$backup_dir/microsoft-edge" ]; then
    if confirm "Do you want to restore Edge data (~/.config/microsoft-edge)?"; then
        rsync -avh --progress "$backup_dir/microsoft-edge/" ~/.config/microsoft-edge
    fi
fi

# Restore GNOME extensions
if [ -d "$backup_dir/gnome-extensions" ]; then
    if confirm "Do you want to restore GNOME extensions (~/.local/share/gnome-shell/extensions)?"; then
        rsync -avh --progress "$backup_dir/gnome-extensions/" ~/.local/share/gnome-shell/extensions
        rsync -avh --progress "$backup_dir/gnome-extensions/system/" /usr/share/gnome-shell/extensions
    fi
fi

# Restore installed packages list
if [ -f "$backup_dir/rpm-packages-list.txt" ]; then
    if confirm "Do you want to restore the list of installed packages?"; then
        echo "To reinstall RPM packages, use:"
        echo "sudo dnf install $(cat $backup_dir/rpm-packages-list.txt | awk '{print $1}' | tr '\n' ' ')"
    fi
fi

if [ -f "$backup_dir/flatpak-apps-list.txt" ]; then
    if confirm "Do you want to restore the list of Flatpak apps?"; then
        echo "To reinstall Flatpak apps, use:"
        echo "flatpak install $(cat $backup_dir/flatpak-apps-list.txt | awk '{print $1}' | tr '\n' ' ')"
    fi
fi

# Restore pip packages
if [ -f "$backup_dir/requirements.txt" ]; then
    if confirm "Do you want to restore pip packages?"; then
        pip install -r "$backup_dir/requirements.txt"
    fi
fi

echo "Restoration completed."
