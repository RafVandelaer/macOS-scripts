<#
.SYNOPSIS
    Microsoft 365 Mailbox Duplicate Cleaner - Identifies and moves duplicate emails to a specified folder.

.DESCRIPTION
    This script scans a Microsoft 365 mailbox folder for duplicate emails and moves them to a target folder.
    It provides options for dry-run mode, content-based duplicate detection, and choosing whether to keep
    the newest or oldest email from each duplicate set.

.PARAMETER Mailbox
    The mailbox to scan for duplicates.

.PARAMETER SourceFolder
    The folder to scan for duplicates. Default is "Inbox".

.PARAMETER TargetFolder
    The folder to move duplicates to. Will be created if it doesn't exist. Default is "Duplicates".

.PARAMETER BatchSize
    Number of messages to process in each batch. Default is 100.

.PARAMETER UseContentHash
    If specified, uses message content for duplicate detection (more accurate but slower).

.PARAMETER KeepOldest
    If specified, keeps the oldest email instead of the newest when duplicates are found.

.PARAMETER DryRun
    If specified, only reports duplicates without moving them.

.PARAMETER LogFile
    Path to log file. Default is "MailboxDuplicateCleaner.log".

.PARAMETER DetailedLog
    If specified, shows all emails scanned and their MD5 hashes.

.PARAMETER Help
    Displays this help information.

.EXAMPLE
    .\MailboxDuplicateCleaner.ps1 -Mailbox "user@example.com" -DryRun
    Performs a dry run to identify duplicates without moving anything.

.EXAMPLE
    .\MailboxDuplicateCleaner.ps1 -Mailbox "user@example.com" -SourceFolder "Sent Items" -TargetFolder "Sent Duplicates"
    Finds duplicates in the "Sent Items" folder and moves them to "Sent Duplicates".

.EXAMPLE
    .\MailboxDuplicateCleaner.ps1 -Mailbox "user@example.com" -UseContentHash -KeepOldest
    Uses content-based duplicate detection and keeps the oldest email in each duplicate set.

.EXAMPLE
    .\MailboxDuplicateCleaner.ps1 -Mailbox "user@example.com" -DetailedLog
    Shows all emails scanned and their MD5 hashes.

.NOTES
    Author: Claude System
    Version: 1.5
    Requires: Exchange Online PowerShell module
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$Mailbox,
    
    [Parameter(Mandatory=$false)]
    [string]$SourceFolder = "Inbox",
    
    [Parameter(Mandatory=$false)]
    [string]$TargetFolder = "Duplicates",
    
    [Parameter(Mandatory=$false)]
    [int]$BatchSize = 100,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseContentHash,
    
    [Parameter(Mandatory=$false)]
    [switch]$KeepOldest,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false)]
    [string]$LogFile = "MailboxDuplicateCleaner.log",
    
    [Parameter(Mandatory=$false)]
    [switch]$DetailedLog,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Display help if requested
if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# Set up logging function
function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Level - $Message"
    
    # Write to console
    switch ($Level) {
        "INFO" { Write-Host $logMessage -ForegroundColor Green }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $logMessage
}

# Display initial information
Write-Log "Microsoft 365 Mailbox Duplicate Cleaner v1.5" "INFO"
Write-Log "Use -Help parameter for detailed instructions" "INFO"

# Check if Exchange Online PowerShell module is installed
if (!(Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Log "ExchangeOnlineManagement module not found. Attempting to install..." "WARNING"
    try {
        Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber
        Write-Log "ExchangeOnlineManagement module installed successfully." "INFO"
    }
    catch {
        Write-Log "Failed to install ExchangeOnlineManagement module. Please install it manually with: Install-Module -Name ExchangeOnlineManagement" "ERROR"
        exit 1
    }
}

# Connect to Exchange Online
try {
    Write-Log "Connecting to Exchange Online..." "INFO"
    Connect-ExchangeOnline -ShowBanner:$false
    Write-Log "Connected to Exchange Online." "INFO"
}
catch {
    Write-Log "Failed to connect to Exchange Online: $_" "ERROR"
    exit 1
}

# Ensure target folder exists
function Ensure-TargetFolderExists {
    try {
        # Get the list of folders
        $folderStats = Get-MailboxFolderStatistics -Identity $Mailbox
        $folderExists = $folderStats | Where-Object { $_.Name -eq $TargetFolder }
        
        if (-not $folderExists) {
            Write-Log "Target folder '$TargetFolder' not found. Creating..." "INFO"
            # Create the folder
            New-MailboxFolder -Identity $Mailbox -Parent "\" -Name $TargetFolder
            Write-Log "Created target folder '$TargetFolder'." "INFO"
        }
        else {
            Write-Log "Target folder '$TargetFolder' already exists." "INFO"
        }
        
        return $true
    }
    catch {
        Write-Log "Failed to create or verify target folder: $_" "ERROR"
        return $false
    }
}

# Get target folder path
function Get-TargetFolderPath {
    try {
        $folderStats = Get-MailboxFolderStatistics -Identity $Mailbox | 
                       Where-Object { $_.Name -eq $TargetFolder }
        
        if ($folderStats) {
            return $folderStats.FolderPath
        }
        else {
            throw "Target folder not found"
        }
    }
    catch {
        throw $_
    }
}

# Get basic hash for an email message
function Get-EmailHash {
    param (
        [Parameter(Mandatory=$true)]
        [object]$Message
    )
    
    # Combine key properties to create a hash
    $hashContent = "$($Message.Subject)$($Message.From)$($Message.ReceivedDateTime)$($Message.Size)"
    
    # Create MD5 hash
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hashBytes = [System.Text.Encoding]::UTF8.GetBytes($hashContent)
    $hashResult = $md5.ComputeHash($hashBytes)
    
    # Convert to hex string
    return [BitConverter]::ToString($hashResult).Replace("-", "")
}

# Get content hash for a message (more accurate but slower)
function Get-EmailContentHash {
    param (
        [Parameter(Mandatory=$true)]
        [object]$Message
    )
    
    try {
        # Get message content
        $content = $Message.Body.Content
        
        if (-not $content) {
            # Try to get the message content using Get-MessageContent
            $messageContent = Get-MessageContent -MessageId $Message.Id
            if ($messageContent) {
                $content = $messageContent.ToString()
            }
        }
        
        if (-not $content) {
            return $null
        }
        
        # Create MD5 hash of content
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hashBytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        $hashResult = $md5.ComputeHash($hashBytes)
        
        # Convert to hex string
        return [BitConverter]::ToString($hashResult).Replace("-", "")
    }
    catch {
        Write-Log "Failed to get content hash for message: $_" "WARNING"
        return $null
    }
}

# Find duplicate emails
function Find-DuplicateEmails {
    try {
        Write-Log "Scanning mailbox '$Mailbox' for duplicates..." "INFO"
        
        $duplicates = @{}
        $processedCount = 0
        $pageSize = $BatchSize
        $page = 1
        $moreMessages = $true
        
        # Get all folders in the mailbox
        $folders = Get-MailboxFolderStatistics -Identity $Mailbox
        
        foreach ($folder in $folders) {
            $folderName = $folder.Name
            Write-Log "Scanning folder '$folderName'..." "INFO"
            
            while ($moreMessages) {
                # Get batch of messages
                $skip = ($page - 1) * $pageSize
                $messages = Search-Mailbox -Identity $Mailbox -SearchQuery "Folder:$folderName" -ResultSize $pageSize -Skip $skip
                
                if ($null -eq $messages -or ($messages -is [array] -and $messages.Count -eq 0)) {
                    $moreMessages = $false
                    continue
                }
                
                # Handle case where only one message is returned (not an array)
                if (-not ($messages -is [array])) {
                    $messages = @($messages)
                }
                
                foreach ($message in $messages) {
                    $primaryHash = Get-EmailHash -Message $message
                    
                    # If using content hash and we already have a primary hash match
                    if ($UseContentHash -and $duplicates.ContainsKey($primaryHash) -and $duplicates[$primaryHash].Count -gt 0) {
                        $contentHash = Get-EmailContentHash -Message $message
                        if ($contentHash) {
                            $hashKey = "${primaryHash}_${contentHash}"
                        }
                        else {
                            $hashKey = $primaryHash
                        }
                    }
                    else {
                        $hashKey = $primaryHash
                    }
                    
                    # Initialize array if needed
                    if (-not $duplicates.ContainsKey($hashKey)) {
                        $duplicates[$hashKey] = @()
                    }
                    
                    # Add message details
                    $duplicates[$hashKey] += @{
                        ID = $message.Id
                        Subject = $message.Subject
                        From = $message.From
                        ReceivedTime = $message.ReceivedDateTime
                        Size = $message.Size
                    }
                    
                    $processedCount++
                    
                    # DetailedLog mode: Show email details and MD5 hash
                    if ($DetailedLog) {
                        Write-Log "Scanned email: Subject='$($message.Subject)', From='$($message.From)', ReceivedTime='$($message.ReceivedDateTime)', Size='$($message.Size)', MD5='$primaryHash'" "INFO"
                    }
                }
                
                $page++
                Write-Log "Processed $processedCount messages so far..." "INFO"
                
                # Break if we got fewer messages than the batch size (we're at the end)
                if ($messages.Count -lt $pageSize) {
                    $moreMessages = $false
                }
            }
        }
        
        # Filter out non-duplicates
        $result = @{}
        foreach ($key in $duplicates.Keys) {
            if ($duplicates[$key].Count -gt 1) {
                $result[$key] = $duplicates[$key]
            }
        }
        
        # Summary of scanned emails
        Write-Log "Total emails scanned: $processedCount" "INFO"
        
        return $result
    }
    catch {
        Write-Log "Error finding duplicates: $_" "ERROR"
        return @{}
    }
}

# Move duplicate emails
function Move-DuplicateEmails {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Duplicates
    )
    
    $totalDuplicateGroups = $Duplicates.Count
    $totalDuplicates = 0
    $movedCount = 0
    
    # Get target folder path
    try {
        $targetFolderPath = Get-TargetFolderPath
    }
    catch {
        Write-Log "Failed to get target folder path: $_" "ERROR"
        return @{
            TotalDuplicateGroups = 0
            TotalDuplicates = 0
            MovedMessages = 0
            DryRun = $DryRun
        }
    }
    
    foreach ($hashKey in $Duplicates.Keys) {
        $messages = $Duplicates[$hashKey]
        
        # Skip if there's only one message (not a duplicate)
        if ($messages.Count -le 1) {
            continue
        }
        
        # Sort messages by date (newest first if keeping newest, oldest first if keeping oldest)
        if ($KeepOldest) {
            $sortedMessages = $messages | Sort-Object ReceivedTime
        }
        else {
            $sortedMessages = $messages | Sort-Object ReceivedTime -Descending
        }
        
        # Keep the first one, move the rest
        $toKeep = $sortedMessages
        $toMove = $sortedMessages[1..($sortedMessages.Count - 1)]
        
        $totalDuplicates += $toMove.Count
        
        # Log what we're doing
        $fromAddress = if ($toKeep.From -is [string]) { $toKeep.From } else { $toKeep.From.Address }
        Write-Log "Found $($toMove.Count) duplicates of email: '$($toKeep.Subject)' from $fromAddress" "INFO"
        
        if (-not $DryRun) {
            foreach ($msg in $toMove) {
                try {
                    # Move message to target folder
                    $result = Move-Message -MessageId $msg.ID -TargetFolderPath $targetFolderPath
                    if ($result) {
                        $movedCount++
                        Write-Log "Moved duplicate message: $($msg.Subject)" "INFO"
                    }
                }
                catch {
                    Write-Log "Failed to move message $($msg.ID): $_" "ERROR"
                }
            }
        }
    }
    
    # Return summary
    return @{
        TotalDuplicateGroups = $totalDuplicateGroups
        TotalDuplicates = $totalDuplicates
        MovedMessages = if ($DryRun) { 0 } else { $movedCount }
        DryRun = $DryRun
    }
}

# Helper function to move a message
function Move-Message {
    param (
        [Parameter(Mandatory=$true)]
        [string]$MessageId,
        
        [Parameter(Mandatory=$true)]
        [string]$TargetFolderPath
    )
    
    try {
        # Move the message to the target folder
        $result = New-MoveRequest -Identity $MessageId -TargetFolder $TargetFolderPath -CompletedRequestAgeLimit 1 -Priority High
        return $true
    }
    catch {
        throw $_
    }
}

# Main execution
try {
    Write-Log "Microsoft 365 Mailbox Duplicate Cleaner starting" "INFO"
    Write-Log "Parameters: Mailbox=$Mailbox, SourceFolder=$SourceFolder, TargetFolder=$TargetFolder, DryRun=$DryRun, UseContentHash=$UseContentHash, KeepOldest=$KeepOldest, DetailedLog=$DetailedLog" "INFO"
    
    # Ensure target folder exists
    if (-not (Ensure-TargetFolderExists)) {
        Write-Log "Exiting due to folder creation failure" "ERROR"
        exit 1
    }
    
    # Find duplicates
    $duplicates = Find-DuplicateEmails
    
    # Move duplicates
    $summary = Move-DuplicateEmails -Duplicates $duplicates
    
    # Print summary
    Write-Log ("-" * 50) "INFO"
    Write-Log "SUMMARY" "INFO"
    Write-Log ("-" * 50) "INFO"
    Write-Log "Duplicate groups found: $($summary.TotalDuplicateGroups)" "INFO"
    Write-Log "Total duplicate messages: $($summary.TotalDuplicates)" "INFO"
    
    if ($DryRun) {
        Write-Log "DRY RUN: No messages were moved" "INFO"
    }
    else {
        Write-Log "Messages moved to '$TargetFolder': $($summary.MovedMessages)" "INFO"
    }
    
    Write-Log ("-" * 50) "INFO"
    
    # Disconnect from Exchange Online
    Disconnect-ExchangeOnline -Confirm:$false
    Write-Log "Disconnected from Exchange Online" "INFO"
}
catch {
    Write-Log "Unhandled error: $_" "ERROR"
    
    # Make sure we disconnect
    try {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    }
    catch {}
    
    exit 1
}