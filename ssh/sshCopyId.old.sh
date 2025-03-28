#!/bin/bash

# Default values
targetOS="Windows"
sshPort=0
DebugLocal=false
DebugRemote=false

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --remoteConnection) remoteConnection="$2"; shift ;;
        --targetOS) targetOS="$2"; shift ;;
        --sshPort) sshPort="$2"; shift ;;
        --i) i="$2"; shift ;;
        --DebugLocal) DebugLocal=true ;;
        --DebugRemote) DebugRemote=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Debugging: Print out the remote connection details
if [ "$DebugLocal" = true ]; then
    echo "Local: Remote Connection: $remoteConnection"
fi

# Log message function
log_message() {
    local message="$1"
    echo "$(date +'%Y-%m-%d %H:%M:%S') DEBUG: $message"
}

# Get remote PowerShell commands
get_remote_powershell_commands() {
    local key="$1"
    cat <<EOL
\$ProgressPreference = 'SilentlyContinue'
\$Debug = \$$DebugRemote
if (\$Debug) {
    Write-Output "Remote: -----------------------------------------------------------------------------------------"
    Write-Output "Remote: Starting Remote Script"
}
\$publicKey = "$key"
if (\$Debug) {
    Write-Output 'Public Key: ' "\$publicKey"
}
\$sshDir = [System.IO.Path]::Combine(\$env:USERPROFILE, '.ssh')
if (\$Debug) {
    Write-Output "Remote: SSH Directory:  \$sshDir"
}
if (-not (Test-Path \$sshDir)) {
    Write-Output 'Creating SSH directory'
    New-Item -ItemType Directory -Force -Path \$sshDir
}
\$authorizedKeysPath = [System.IO.Path]::Combine(\$sshDir, 'authorized_keys')
if (\$Debug) {
    Write-Output "Remote: Authorized Keys Path: \$authorizedKeysPath"
}
if (-not (Test-Path \$authorizedKeysPath)) {
    Write-Output 'Remote: Creating authorized_keys file'
    New-Item -ItemType File -Force -Path \$authorizedKeysPath
}
\$patternString = [Regex]::Escape("\$publicKey")
if (\$Debug) {
    Write-Output "Remote: Pattern String \$patternString"
}
if (Select-String -Pattern \$patternString -Path \$authorizedKeysPath) {
    Write-Output "Remote: Public key already in authorized_keys"
} else {
    Add-Content -Path \$authorizedKeysPath -Value \$publicKey
    Write-Output "Remote: Added public key to authorized_keys"
}
if (\$Debug) {
    Write-Output "Remote: Ending Remote Script"
    Write-Output "Remote: -----------------------------------------------------------------------------------------"
}
EOL
}

# Get remote Linux commands
get_remote_linux_commands() {
    local key="$1"
    cat <<EOL
debug=\$([ "$DebugRemote" = true ] && echo 1 || echo 0)
publicKey="$key"
if [ ! -d "\$HOME/.ssh" ]; then
    mkdir -p "\$HOME/.ssh"
    [ \$debug -eq 1 ] && echo "Remote: Creating ~/.ssh"
fi
chmod 700 "\$HOME/.ssh"
authorized_keys="\$HOME/.ssh/authorized_keys"
[ \$debug -eq 1 ] && echo "Remote: authorized_keys = \$authorized_keys"
if [ ! -f "\$authorized_keys" ]; then
    touch "\$authorized_keys"
    [ \$debug -eq 1 ] && echo "Remote: Created \$authorized_keys"
fi
if ! grep -qF "\$publicKey" "\$authorized_keys"; then
    echo "\$publicKey" >> "\$authorized_keys"
    [ \$debug -eq 1 ] && echo "Remote: Public key added to authorized_keys."
else
    [ \$debug -eq 1 ] && echo "Remote: Public key is already present in authorized_keys."
fi
chmod 600 "\$authorized_keys"
echo "Remote: Public key is now available on \$(hostname) (\$(hostname -I | awk '{print \$1}'))"
EOL
}

# Remote connection details validation
if [[ ! "$remoteConnection" =~ ^([^@]+)@([^@]+)$ ]]; then
    echo "Invalid remote connection format. Use user@host."
    exit 1
fi

remoteUser=${BASH_REMATCH[1]}
remoteHost=${BASH_REMATCH[2]}

# Set SSH port based on target OS
if [ "$targetOS" = "WSL" ]; then
    [ $sshPort -eq 0 ] && sshPort=2222
else
    [ $sshPort -eq 0 ] && sshPort=22
fi

# Determine public key path
if [ -z "$i" ]; then
	publicKeyPath="$HOME/.ssh/id_rsa.pub"
else
    publicKeyPath="$i"
fi

# Verify public key file exists
if [ ! -f "$publicKeyPath" ]; then
    echo "Public key file not found at $publicKeyPath"
    exit 1
fi

publicKeyContent=$(<"$publicKeyPath")

# Debug: Print the remote script before encoding
if [ "$targetOS" = "Windows" ]; then
    remoteCommands=$(get_remote_powershell_commands "$publicKeyContent")	
    if [ "$DebugLocal" = true ]; then
        echo "Local: -----------------------------------------------------------------------------------------"
        echo "Local: Remote PowerShell Script:"
        echo "$remoteCommands"
        echo "Local: -----------------------------------------------------------------------------------------"
    fi
    encodedScript=$(echo "$remoteCommands" | iconv -f UTF-8 -t UTF-16LE | base64 -w 0)
	# encodedScript=[Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($remoteCommands))\
    if [ "$DebugLocal" = true ]; then
        echo "Local: Before sshCommand execution"
    fi
    output=$(echo "$remoteCommands" | ssh -p $sshPort "$remoteConnection" powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand "$encodedScript")
    result=$?
elif [[ "$targetOS" = "Linux" || "$targetOS" = "WSL" ]]; then
    remoteCommands=$(get_remote_linux_commands "$publicKeyContent")
    if [ "$DebugLocal" = true ]; then
        echo "Local: -----------------------------------------------------------------------------------------"
        echo "Local: Remote Bash Script:"
        echo "$remoteCommands"
        echo "Local: -----------------------------------------------------------------------------------------"
    fi
    output=$(echo "$remoteCommands" | ssh -p $sshPort "$remoteConnection" "bash -s")
    # output=$(ssh -p $sshPort "$remoteConnection" "bash -s" <<< "$remoteCommands")
    result=$?
fi

# Check result and output
if [ $result -eq 0 ]; then
    echo "Local: Public key added to authorized_keys on $remoteHost via SSH"
else
    echo "ssh failed! $output"
    exit 1
fi

if [ "$DebugLocal" = true ]; then
    echo "Local: After sshCommand execution"
    echo "Local: SSH Output:"
    echo "$output"
    echo "Local: Finished SSH execution"
fi
