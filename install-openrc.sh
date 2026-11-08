#!/usr/bin/env bash

# Copyright (C) 2024-2026 Arcitec
# SPDX-License-Identifier: GPL-2.0-only

# OpenRC variant of "install.sh", for distros using OpenRC user services
# (such as Gentoo with "pam_openrc" and OpenRC 0.60 or newer).

set -e

# Set current working dir to the script directory.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# We must be running as a regular user to control the current user's services.
if [[ "${EUID}" == "0" ]]; then
    echo "Error: This script must run with local user privileges, NOT as root!"
    exit 1
fi

_ACTION="install"
_OPTION_COUNT="0"
while getopts ":iued" option; do
    ((_OPTION_COUNT += 1))
    case "${option}" in
    i)
        _ACTION="install"
        ;;
    u)
        _ACTION="uninstall"
        ;;
    e)
        _ACTION="enable-user-startup"
        ;;
    d)
        _ACTION="disable-user-startup"
        ;;
    *)
        echo "Usage: $0 [-i] [-u] [-e] [-d]"
        echo
        echo "Options:"
        echo " -i  Install, and enable startup for the current user (default if no options provided)."
        echo " -u  Uninstall (stops and disables the service for the current user first)."
        echo " -e  Enable startup for the current user."
        echo " -d  Disable startup for the current user."
        exit 1
        ;;
    esac
done

if [[ "${_OPTION_COUNT}" -gt 1 ]]; then
    echo "Error: You can only use one option per command execution. Please try again."
    exit
fi

UNIT_NAME="discord-flatpak-rpc-bridge"
INIT_DIR="/etc/user/init.d"

if ! command -v socat >/dev/null; then
    echo "Error: \"socat\" is required. Install it first (Gentoo: emerge net-misc/socat)."
    exit 1
fi

if [[ "${_ACTION}" == "install" ]]; then
    echo "Installing Discord Native-to-Flatpak RPC Bridge..."
    set -x

    # Install the init script in the system-wide user service location.
    sudo install -D -t "${INIT_DIR}" -m 755 "openrc/${UNIT_NAME}"

    # Enable and start the bridge for the currently active user.
    # NOTE: Other users must run "-e" themselves, since OpenRC has no equivalent
    # of systemd's "--global enable" for user services.
    rc-update --user add "${UNIT_NAME}" default
    rc-service --user "${UNIT_NAME}" start || true

    rc-service --user "${UNIT_NAME}" status
elif [[ "${_ACTION}" == "uninstall" ]]; then
    echo "Removing Discord Native-to-Flatpak RPC Bridge..."
    set -x

    # NOTE: Other users must run "-d" themselves before uninstalling, otherwise
    # they are left with dangling runlevel links in their "~/.config/rc".
    rc-service --user "${UNIT_NAME}" stop || true
    rc-update --user del "${UNIT_NAME}" default || true

    sudo rm -fv "${INIT_DIR}/${UNIT_NAME}"
elif [[ "${_ACTION}" == "enable-user-startup" ]]; then
    echo "Enabling automatic startup of the Discord Native-to-Flatpak RPC Bridge for the currently active user (\"${USER}\")..."
    set -x

    rc-update --user add "${UNIT_NAME}" default || echo "Service is not installed?"
    rc-service --user "${UNIT_NAME}" start || true
elif [[ "${_ACTION}" == "disable-user-startup" ]]; then
    echo "Disabling automatic startup of the Discord Native-to-Flatpak RPC Bridge for the currently active user (\"${USER}\")..."
    set -x

    rc-service --user "${UNIT_NAME}" stop || true
    rc-update --user del "${UNIT_NAME}" default || echo "Service is not installed?"
fi

set +x
echo "Process complete: \"${_ACTION}\"."
