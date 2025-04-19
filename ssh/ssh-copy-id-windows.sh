#!/bin/bash

# Default values
sshPort=22
DebugLocal=false
DebugRemote=false
identity_file="$HOME/.ssh/id_rsa.pub"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        *@*)
            # Handle arguments of the form user@host
            remoteConnection="$1"
            remoteUser="${1%@*}"   # Extract the part before '@'
            remoteHost="${1#*@}"   # Extract the part after '@'
            ;;
        -p) sshPort="$2"; shift ;;
        -i) identity_file="$2"; shift ;;
        --DebugLocal) DebugLocal=true ;;
        --DebugRemote) DebugRemote="true" ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Debugging: Print out the remote connection details
if [ "$DebugLocal" = true ]; then
    echo "Local: Found user@host format:"
    echo "Local: Connection: $remoteConnection"
    echo "Local: User: $remoteUser"
    echo "Local: Host: $remoteHost"
fi

# Log message function
log_message() {
    local message="$1"
    echo "$(date +'%Y-%m-%d %H:%M:%S') DEBUG: $message"
}

# Get remote PowerShell commands
get_remote_powershell_commands() {
    local key="$1"

    if [ $DebugRemote = true ]; then
        ps_debug_remote='$true'
    else
        ps_debug_remote='$false'
    fi

    cat <<EOL
\$ProgressPreference = 'SilentlyContinue'
\$Debug = $ps_debug_remote
if (\$Debug) {
    Write-Output "Remote: Starting Remote Script"
}
\$publicKey = "$key"
if (\$Debug) {
    Write-Output "Remote: Public Key: \$publicKey"
}
\$sshDir = [System.IO.Path]::Combine(\$env:USERPROFILE, '.ssh')
if (\$Debug) {
    Write-Output "Remote: SSH Directory:  \$sshDir"
}
if (-not (Test-Path \$sshDir)) {
    Write-Output 'Creating SSH directory'
    New-Item -ItemType Directory -Force -Path \$sshDir | Out-Null
}
\$authorizedKeysPath = [System.IO.Path]::Combine(\$sshDir, 'authorized_keys')
if (\$Debug) {
    Write-Output "Remote: Authorized Keys Path: \$authorizedKeysPath"
}
if (-not (Test-Path \$authorizedKeysPath)) {
    Write-Output 'Remote: Creating authorized_keys file'
    New-Item -ItemType File -Force -Path \$authorizedKeysPath | Out-Null
}
\$patternString = [Regex]::Escape("\$publicKey")
if (\$Debug) {
    Write-Output "Remote: Pattern String \$patternString"
}
if (Select-String -Pattern \$patternString -Path \$authorizedKeysPath) {
    Write-Output "Remote: Public key already in authorized_keys"
} else {
    Add-Content -Path \$authorizedKeysPath -Value \$publicKey | Out-Null
    Write-Output "Remote: Added public key to authorized_keys"
}
if (\$Debug) {
    Write-Output "Remote: Ending Remote Script"
}
EOL
}

# Verify public key file exists
if [ ! -f "$identity_file" ]; then
    echo "Public key file not found at $identity_file"
    exit 1
fi

publicKeyContent=$(<"$identity_file")

# Debug: Print the remote script before encoding

remoteCommands=$(get_remote_powershell_commands "$publicKeyContent")
if [ "$DebugLocal" = true ]; then
    echo "Local: -----------------------------------------------------------------------------------------"
    echo "Local: Remote PowerShell Script:"
    echo "$remoteCommands"
    echo "Local: -----------------------------------------------------------------------------------------"
fi
if [ "$DebugLocal" = true ]; then
    echo "Local: Before sshCommand execution: -p $sshPort $remoteConnection"
fi
output=$(ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password -p $sshPort  "$remoteConnection" "$remoteCommands")
result=$?

if [ "$DebugLocal" = true ]; then
    echo "Local: After sshCommand execution"
    echo "Local: SSH returned $result with output:"    
    echo "Local: -----------------------------------------------------------------------------------------"
    echo "$output"
    echo "Local: -----------------------------------------------------------------------------------------"
    echo "Local: Finished SSH execution"
fi
exit $result
