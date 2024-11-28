# Define mailbox and target folder
$mailbox = "user@example.com"
$targetFolderName = "Double check"
$dryRun = $true # Set to $false to perform actual moves

# Load Exchange Online PowerShell module
Import-Module ExchangeOnlineManagement

# Connect to Exchange Online
Connect-ExchangeOnline -UserPrincipalName $mailbox -ShowProgress $true

# Get mailbox folders
$folders = Get-MailboxFolderStatistics -Identity $mailbox | Where-Object { $_.FolderType -eq "User Created" }

# Check and create 'Double check' folder if it doesn't exist
$targetFolder = Get-MailboxFolderStatistics -Identity $mailbox -FolderScope "All" | Where-Object { $_.Name -eq $targetFolderName }
if (-not $targetFolder -and -not $dryRun) {
    New-MailboxFolder -Identity "$mailbox:\$targetFolderName"
    Write-Output "Created folder: $targetFolderName"
} else {
    Write-Output "Folder already exists: $targetFolderName"
}

# Iterate through folders and find duplicate emails
foreach ($folder in $folders) {
    $folderPath = $folder.FolderPath -replace '/', '\'
    $emails = Get-Content -Path "$mailbox\$folderPath"

    Write-Output "Checking folder: $folderPath"

    $emailHashes = @{}
    foreach ($email in $emails) {
        $hash = $email.Body.GetHashCode()

        if ($emailHashes.ContainsKey($hash)) {
            if ($dryRun) {
                Write-Output "Duplicate email found (Dry Run): $($email.Subject)"
            } else {
                # Move duplicate email to 'Double check' folder
                $email | Move-MailboxItem -DestinationFolder "$mailbox:\$targetFolderName"
                Write-Output "Duplicate email moved to 'Double check' folder: $($email.Subject)"
            }
        } else {
            $emailHashes[$hash] = $email
        }
    }
}

# Disconnect from Exchange Online
Disconnect-ExchangeOnline -Confirm:$false
Write-Output "Disconnected from Exchange Online"
