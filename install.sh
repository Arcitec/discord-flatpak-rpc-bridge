#!/usr/bin/env bash

# Copyright (C) 2024 Arcitec
# SPDX-License-Identifier: GPL-2.0-only

set -e

# Set current working dir to the script directory.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# We must be running as a regular user to control the current user's socket.
if [[ "${EUID}" == "0" ]]; then
    echo "Error: This script must run with local user privileges, NOT as root!"
    exit 1
fi

_ACTION="install"
_OPTION_COUNT="0"
while getopts ":iumaed" option; do
    ((_OPTION_COUNT += 1))
    case "${option}" in
    i)
        _ACTION="install"
        ;;
    u)
        _ACTION="uninstall"
        ;;
    m)
        _ACTION="manual-startup"
        ;;
    a)
        _ACTION="automatic-startup"
        ;;
    e)
        _ACTION="enable-user-startup"
        ;;
    d)
        _ACTION="disable-user-startup"
        ;;
    *)
        echo "Usage: $0 [-i] [-u] [-m] [-a] [-e] [-d]"
        echo
        echo "Options:"
        echo " -i  Install (default if no options provided)."
        echo " -u  Uninstall."
        echo " -m  Switch to manual per-user startup handling (for total control)."
        echo " -a  Switch to automatic per-user startup handling (this is the default mode)."
        echo " -e  Enable startup for the current user (only works in manual mode)."
        echo " -d  Disable startup for the current user (only works in manual mode)."
        exit 1
        ;;
    esac
done

if [[ "${_OPTION_COUNT}" -gt 1 ]]; then
    echo "Error: You can only use one option per command execution. Please try again."
    exit
fi

UNIT_NAME="discord-flatpak-rpc-bridge"
UNIT_FILES=("${UNIT_NAME}"{.service,.socket})

if [[ "${_ACTION}" == "install" ]]; then
    echo "Installing Discord Native-to-Flatpak RPC Bridge..."
    set -x

    # Install the unit files in the system-wide user unit location.
    # NOTE: This is the correct location for "local administrator-installed units".
    sudo install -D -t "/etc/systemd/user" -m "u=rw,go=r,a-s" "${UNIT_FILES[@]}"

    # Update systemctl's internal state to detect the new unit files.
    # NOTE: Yes, the "--user" variant is required for a complete reload.
    sudo systemctl daemon-reload
    systemctl --user daemon-reload

    # Automatically enable the socket bridge for all users on the entire system.
    # NOTE: Do NOT enable the service. It auto-starts when the socket is first used.
    sudo systemctl --global enable "${UNIT_NAME}.socket"

    # Now start the socket for the currently active user.
    # NOTE: If the system has multiple logged-in users, they either need to log out,
    # restart the machine, or manually run this command to start their own sockets.
    # NOTE: We use "or-true" to continue executing if the socket couldn't start.
    systemctl --user start "${UNIT_NAME}.socket" || true

    # Check the status of the user's socket.
    # NOTE: This is mostly useful for seeing startup error messages, which will
    # never happen except if the target socket file cannot be created.
    # SEE: Read the ".socket" file for details about why it might fail.
    systemctl --user --no-pager --full status "${UNIT_NAME}.socket"
elif [[ "${_ACTION}" == "uninstall" ]]; then
    echo "Removing Discord Native-to-Flatpak RPC Bridge..."
    set -x

    # Stop the currently active user's socket and service.
    # NOTE: The socket-file and all directories will still remain on disk until
    # restart (when the per-user runtime "tmpfs" is wiped), but will not accept
    # any connections, so it's basically like it doesn't exist.
    # NOTE: If there are multiple logged-in users, the others may still continue
    # running the units after removal, but they will disappear after reboot. We
    # cannot stop the services for anyone except the current user here!
    # NOTE: This command stops EVERY unit regardless of the status of the others,
    # but will exit with a non-zero status code afterwards if any of the units
    # were missing (mainly if they're already uninstalled), hence the "or-true".
    # NOTE: We must disable both the socket and service (it may have started).
    systemctl --user stop "${UNIT_FILES[@]}" || true

    # Disable the unit files for all users.
    # NOTE: The ".service" should NEVER be enabled, we just remove it to be sure.
    # NOTE: We disable warnings to suppress a wall of text when units don't exist.
    sudo systemctl --global --no-warn disable "${UNIT_FILES[@]}" || echo "Units are not installed?"

    # Remove the actual unit files from disk.
    sudo find "/etc/systemd/user" -maxdepth 1 -name "${UNIT_NAME}.*" -print -delete

    # Update systemctl's internal state to detect the removed unit files.
    sudo systemctl daemon-reload
    systemctl --user daemon-reload
elif [[ "${_ACTION}" == "manual-startup" ]]; then
    echo "Disabling automatic startup of the Discord Native-to-Flatpak RPC Bridge for all users..."
    set -x

    # Disable the global "start on all user logins" status.
    # NOTE: See "uninstall" for more details about how this works.
    # NOTE: Will NOT remove manually created "enable-user-startup" startup links,
    # which will have to be removed again by the user via "disable-user-startup",
    # otherwise the service still starts for that user (perhaps what they want).
    sudo systemctl --global --no-warn disable "${UNIT_FILES[@]}" || echo "Units are not installed?"
elif [[ "${_ACTION}" == "automatic-startup" ]]; then
    echo "Enabling automatic startup of the Discord Native-to-Flatpak RPC Bridge for all users..."
    set -x

    # Enable the global "start on all user logins" status.
    # NOTE: See "install" for more details about how this works.
    sudo systemctl --global enable "${UNIT_NAME}.socket" || echo "Units are not installed?"
elif [[ "${_ACTION}" == "enable-user-startup" ]]; then
    echo "Enabling automatic startup of the Discord Native-to-Flatpak RPC Bridge for the currently active user (\"${USER}\")..."
    set -x

    # Enable (and start) the socket bridge for the current user.
    systemctl --user --now enable "${UNIT_NAME}.socket" || echo "Units are not installed?"
elif [[ "${_ACTION}" == "disable-user-startup" ]]; then
    echo "Disabling automatic startup of the Discord Native-to-Flatpak RPC Bridge for the currently active user (\"${USER}\")..."
    set -x

    # Disable (and stop) the socket bridge for the current user.
    systemctl --user --no-warn --now disable "${UNIT_FILES[@]}" || echo "Units are not installed?"
fi

set +x
echo "Process complete: \"${_ACTION}\"."
