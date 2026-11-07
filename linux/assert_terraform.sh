#!/bin/bash

# Assert Terraform Version
#
# Ensures a Terraform binary satisfying automation/terraform/providers.tf's
# required_version constraint is installed and on PATH.
#
# Terraform isn't available via the standard apt repositories without first
# adding HashiCorp's own apt repo, so this downloads the official release
# zip directly from releases.hashicorp.com instead -- same approach as
# assert_chrome_installed.sh uses for Chrome's .deb. Installs to
# /usr/local/bin when run with sudo access, falling back to ~/.local/bin
# otherwise (consistent with this project's no-sudo-friendly client setup).
#
# This script is idempotent and can be run multiple times safely.

set -uo pipefail

# Parse arguments
DEBUG=false
CHECK=false
TERRAFORM_VERSION=""  # Empty = resolve the latest version satisfying required_version

script_path="${BASH_SOURCE[0]}"
script_name="$(basename "$script_path")"
dir="$(cd "$(dirname "$script_path")" && pwd)"
root_dir="$(cd "$dir/.." && pwd)"

while [[ $# -gt 0 ]]; do
    case $1 in
        --Debug|-d)
            DEBUG=true
            ;;
        --Check|-c)
            CHECK=true
            ;;
        --TerraformVersion|-tv)
            TERRAFORM_VERSION=$2
            shift
            ;;
        *)
            echo "Error   : Unrecognized argument $1 in $script_name." >&2
            echo "Usage   : $script_name [--Debug|-d] [--Check|-c] [--TerraformVersion|-tv <version>]" >&2
            exit 1
            ;;
    esac
    shift
done

PROVIDERS_TF="$root_dir/automation/terraform/providers.tf"
REQUIRED_CONSTRAINT="1.9"
if [[ -f "$PROVIDERS_TF" ]]; then
    _parsed="$(grep -oP 'required_version\s*=\s*">=\s*\K[0-9]+\.[0-9]+' "$PROVIDERS_TF" | head -1)"
    [[ -n "$_parsed" ]] && REQUIRED_CONSTRAINT="$_parsed"
    unset _parsed
fi
$DEBUG && echo "Debug   : Required Terraform version (from providers.tf): >= $REQUIRED_CONSTRAINT"

version_ge() {
    # Returns 0 if $1 >= $2 (dotted numeric versions).
    [[ "$1" == "$2" ]] && return 0
    local higher
    higher="$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)"
    [[ "$higher" == "$1" ]]
}

current_version=""
if command -v terraform >/dev/null 2>&1; then
    current_version="$(terraform version -json 2>/dev/null | grep -oP '"terraform_version":\s*"\K[0-9.]+' || true)"
    [[ -z "$current_version" ]] && current_version="$(terraform version 2>/dev/null | head -1 | grep -oP 'v\K[0-9.]+' || true)"
fi

if [[ -n "$current_version" ]]; then
    $DEBUG && echo "Debug   : Current Terraform: $current_version ($(command -v terraform))"
    if version_ge "$current_version" "$REQUIRED_CONSTRAINT"; then
        echo "Info    : Terraform $current_version already satisfies >= $REQUIRED_CONSTRAINT"
        $CHECK && exit 0
        exit 0
    fi
    echo "Info    : Terraform $current_version is older than required >= $REQUIRED_CONSTRAINT"
else
    echo "Info    : Terraform is not installed"
fi

if $CHECK; then
    echo "Check   : Terraform (>= $REQUIRED_CONSTRAINT) would be downloaded and installed"
    exit 1
fi

if [[ -z "$TERRAFORM_VERSION" ]]; then
    echo "Info    : Resolving latest Terraform release..."
    TERRAFORM_VERSION="$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | grep -oP '"current_version":\s*"\K[0-9.]+' || true)"
    if [[ -z "$TERRAFORM_VERSION" ]]; then
        echo "Error   : Could not resolve the latest Terraform version from checkpoint-api.hashicorp.com" >&2
        exit 1
    fi
fi
$DEBUG && echo "Debug   : Target Terraform version: $TERRAFORM_VERSION"

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64) TF_ARCH="amd64" ;;
    aarch64|arm64) TF_ARCH="arm64" ;;
    *)
        echo "Error   : Unsupported architecture for Terraform download: $ARCH" >&2
        exit 1
        ;;
esac

TF_ZIP_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TF_ARCH}.zip"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Info    : Downloading Terraform $TERRAFORM_VERSION from $TF_ZIP_URL..."
if ! curl -sL -o "$TMP_DIR/terraform.zip" "$TF_ZIP_URL"; then
    echo "Error   : Failed to download Terraform from $TF_ZIP_URL" >&2
    exit 1
fi

if ! unzip -q -o "$TMP_DIR/terraform.zip" -d "$TMP_DIR"; then
    echo "Error   : Failed to extract the downloaded Terraform archive" >&2
    exit 1
fi
chmod +x "$TMP_DIR/terraform"

if sudo -n true 2>/dev/null; then
    INSTALL_DIR="/usr/local/bin"
    sudo install -m 0755 "$TMP_DIR/terraform" "$INSTALL_DIR/terraform"
else
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
    install -m 0755 "$TMP_DIR/terraform" "$INSTALL_DIR/terraform"
    echo "Info    : Installed without sudo to $INSTALL_DIR (ensure it's on PATH)"
fi

if "$INSTALL_DIR/terraform" version 2>&1 | head -1 | grep -q "$TERRAFORM_VERSION"; then
    echo "Result  : Terraform $TERRAFORM_VERSION installed successfully at $INSTALL_DIR/terraform"
else
    echo "Warning : Terraform installed to $INSTALL_DIR but version verification was inconclusive"
fi
