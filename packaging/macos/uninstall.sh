#!/bin/sh
set -eu

if [ "$EUID" -ne 0 ]; then
    echo "This script needs to run as root"
    exit 1
fi

while true; do
    read -p "Are you sure you want to remove Hyperpass from your system? [Y/N] " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) echo "Aborted"; exit;;
        * ) echo "Please answer yes or no.";;
    esac
done

DELETE_VMS=0

while true; do
    read -p "Do you want to delete all your Hyperpass VMs and daemon data too? [Y/N] " yn
    case $yn in
        [Yy]* ) DELETE_VMS=1; break;;
        [Nn]* ) DELETE_VMS=0; break;;
        * ) echo "Please answer yes or no.";;
    esac
done

if [ $DELETE_VMS -eq 1 ]; then
    echo "Removing VMs:"
    sudo -u "$(logname)" hyperpass delete -vv --purge --all || echo "Failed to delete hyperpass VMs from underlying driver" >&2

fi

LAUNCH_AGENT_DEST="/Library/LaunchDaemons/com.elemento.hyperpassd.plist"

echo .
echo "Removing the Hyperpass daemon launch agent:"
launchctl unload -w "$LAUNCH_AGENT_DEST"

if [ $DELETE_VMS -eq 1 ]; then
    echo "Removing daemon data:"
    rm -rfv "/var/root/Library/Application Support/hyperpassd"
    rm -rfv "/var/root/Library/Application Support/hyperpass-client-certificate"
    rm -rfv "/var/root/Library/Preferences/hyperpassd"
    rm -fv "/Library/Keychains/hyperpass_root_cert.pem"
    rm -rfv "/usr/local/etc/hyperpassd"
fi

echo .
echo "Removing Hyperpass:"
rm -fv "$LAUNCH_AGENT_DEST"

rm -fv /usr/local/bin/hyperpass
rm -rfv /Applications/Hyperpass.app

rm -rfv "/Library/Application Support/com.elemento.hyperpass"
rm -rfv "/var/root/Library/Caches/hyperpassd"

# GUI Autostart
rm -fv "$HOME/Library/LaunchAgents/com.elemento.hyperpass.gui.autostart.plist"

# User-specific client certificates and GUI data
rm -rfv "$HOME/Library/Application Support/hyperpass-client-certificate"
rm -rfv "$HOME/Library/Application Support/com.elemento.hyperpassGui"
rm -rfv "$HOME/Library/Preferences/hyperpass"

# Bash completions
rm -rfv "/usr/local/etc/bash_completion.d/hyperpass"
rm -rf "/opt/local/share/bash-completion/completions/hyperpass"

# Log files
rm -rfv "/Library/Logs/Hyperpass"

echo .
echo "Removing package installation receipts"
rm -fv "/private/var/db/receipts/com.elemento.hyperpass.hyperpassd.bom"
rm -fv "/private/var/db/receipts/com.elemento.hyperpass.hyperpassd.plist"
rm -fv "/private/var/db/receipts/com.elemento.hyperpass.hyperpass.bom"
rm -fv "/private/var/db/receipts/com.elemento.hyperpass.hyperpass.plist"

echo .
echo "Uninstall complete"

if [ $DELETE_VMS -eq 0 ]; then
    echo "Your Hyperpass VMs were preserved in /var/root/Library/Application Support/hyperpassd"
fi
