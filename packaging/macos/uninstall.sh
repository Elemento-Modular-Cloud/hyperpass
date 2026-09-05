#!/bin/sh
set -eu

if [ "$EUID" -ne 0 ]; then
    echo "This script needs to run as root"
    exit 1
fi

while true; do
    read -p "Are you sure you want to remove Electros LaunchPad from your system? [Y/N] " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) echo "Aborted"; exit;;
        * ) echo "Please answer yes or no.";;
    esac
done

DELETE_VMS=0

while true; do
    read -p "Do you want to delete all your Electros LaunchPad VMs and daemon data too? [Y/N] " yn
    case $yn in
        [Yy]* ) DELETE_VMS=1; break;;
        [Nn]* ) DELETE_VMS=0; break;;
        * ) echo "Please answer yes or no.";;
    esac
done

if [ $DELETE_VMS -eq 1 ]; then
    echo "Removing VMs:"
    sudo -u "$(logname)" elp delete -vv --purge --all || echo "Failed to delete elp VMs from underlying driver" >&2

fi

LAUNCH_AGENT_DEST="/Library/LaunchDaemons/com.elemento.elpd.plist"
API_LAUNCH_AGENT_DEST="/Library/LaunchDaemons/com.elemento.elp-api.plist"

echo .
echo "Removing the Electros LaunchPad daemon launch agent:"
launchctl unload -w "$LAUNCH_AGENT_DEST" || true

echo "Removing the Electros LaunchPad API launch agent:"
launchctl unload -w "$API_LAUNCH_AGENT_DEST" || true

if [ $DELETE_VMS -eq 1 ]; then
    echo "Removing daemon data:"
    rm -rfv "/var/root/Library/Application Support/elpd"
    rm -rfv "/var/root/Library/Application Support/elp-client-certificate"
    rm -rfv "/var/root/Library/Preferences/elpd"
    rm -fv "/Library/Keychains/elp_root_cert.pem"
    rm -rfv "/usr/local/etc/elpd"
fi

echo .
echo "Removing Electros LaunchPad:"
rm -fv "$LAUNCH_AGENT_DEST"
rm -fv "$API_LAUNCH_AGENT_DEST"

rm -fv /usr/local/bin/elp
rm -rfv "/Applications/Electros LaunchPad.app"

rm -rfv "/Library/Application Support/com.elemento.elp"
rm -rfv "/var/root/Library/Caches/elpd"

# GUI Autostart
rm -fv "$HOME/Library/LaunchAgents/com.elemento.elp.gui.autostart.plist"

# User-specific client certificates and GUI data
rm -rfv "$HOME/Library/Application Support/elp-client-certificate"
rm -rfv "$HOME/Library/Application Support/com.elemento.elpGui"
rm -rfv "$HOME/Library/Preferences/elp"

# Bash completions
rm -rfv "/usr/local/etc/bash_completion.d/elp"
rm -rf "/opt/local/share/bash-completion/completions/elp"

# Log files
rm -rfv "/Library/Logs/Electros LaunchPad"

echo .
echo "Removing package installation receipts"
rm -fv "/private/var/db/receipts/com.elemento.elp.elpd.bom"
rm -fv "/private/var/db/receipts/com.elemento.elp.elpd.plist"
rm -fv "/private/var/db/receipts/com.elemento.elp.elp.bom"
rm -fv "/private/var/db/receipts/com.elemento.elp.elp.plist"
rm -fv "/private/var/db/receipts/com.elemento.elp.elp_api.bom"
rm -fv "/private/var/db/receipts/com.elemento.elp.elp_api.plist"

echo .
echo "Uninstall complete"

if [ $DELETE_VMS -eq 0 ]; then
    echo "Your Electros LaunchPad VMs were preserved in /var/root/Library/Application Support/elpd"
fi
