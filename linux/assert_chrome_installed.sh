#!/bin/bash

# Assert Chrome Installed
#
# Ensures Google Chrome is installed and set as the default web browser.
# Chrome isn't available via the standard apt repositories, so this downloads
# Google's official .deb package directly and installs it via apt.
#
# This script is idempotent and can be run multiple times safely.

# Parse arguments
DEBUG=false
CHECK=false

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d)
            DEBUG=true
            ;;
        --Check|-c)
            CHECK=true
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name."
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c]"
            exit 1
            ;;
    esac
    shift
done

CHROME_DEB_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"

if dpkg-query -W -f='${Status}' google-chrome-stable 2>/dev/null | grep -q "install ok installed"; then
    $DEBUG && echo "Debug   : google-chrome-stable is already installed."
else
    if $CHECK; then
        echo "Check   : google-chrome-stable would be downloaded and installed."
    else
        echo "Info    : Downloading Google Chrome..."
        TMP_DEB="$(mktemp --suffix=.deb)"
        if ! wget -q -O "$TMP_DEB" "$CHROME_DEB_URL"; then
            echo "Error   : Failed to download Google Chrome from $CHROME_DEB_URL" >&2
            rm -f "$TMP_DEB"
            exit 1
        fi

        echo "Info    : Installing Google Chrome..."
        if sudo apt install -y "$TMP_DEB"; then
            echo "Result  : Google Chrome installed successfully."
        else
            echo "Error   : Failed to install Google Chrome." >&2
            rm -f "$TMP_DEB"
            exit 1
        fi
        rm -f "$TMP_DEB"
    fi
fi

# Set as default web browser. xdg-settings rewrites mimeapps.list for
# text/html and x-scheme-handler/http(s) — this is what fixes the case where
# XFCE's web-browser association points at a browser that was never installed.
if ! $CHECK; then
    if command -v xdg-settings >/dev/null 2>&1 && command -v google-chrome >/dev/null 2>&1; then
        xdg-settings set default-web-browser google-chrome.desktop
        echo "Info    : Set google-chrome.desktop as the default web browser."
    fi
else
    echo "Check   : Would set google-chrome.desktop as the default web browser."
fi
