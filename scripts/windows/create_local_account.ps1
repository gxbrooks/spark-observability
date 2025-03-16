param (
    [switch]$Force
)

# Define the username and password
$username = "gxbrooks"
$password = "localgxbro77;;"

# Get the hostname
$hostname = (Get-WmiObject -Class Win32_ComputerSystem).Name

# Check if the user exists
$user = Get-LocalUser -Name $username -ErrorAction SilentlyContinue

if ($user) {
    Write-Output "User '$username' already exists."
} elseif ($Force) {
    Write-Output "Creating the user '$username'"
    New-LocalUser -Name $username `
        -Description "Local account for Ansible" `
        -Password (ConvertTo-SecureString $password -AsPlainText -Force) `
        -PasswordNeverExpires
} else {
    Write-Output "User '$username' does not exist."
}

# Define the groups
$groups = @("Administrators", "Users", "docker-users", "OpenSSH Users", "Performance Log Users")

foreach ($group in $groups) {
    $groupMembers = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue
    $prefixedUsername = "$hostname\$username"
    if ($groupMembers -and $groupMembers.Name -contains $prefixedUsername) {
        Write-Output "User '$prefixedUsername' is already a member of the group '$group'."
    } elseif ($Force) {
        Write-Output "Adding user '$prefixedUsername' to the group '$group'."
        Add-LocalGroupMember -Member $username -Group $group -ErrorAction SilentlyContinue
    } else {
        Write-Output "User '$prefixedUsername' is not in the group '$group'."
    }
}
