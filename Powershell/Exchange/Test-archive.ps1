<#
.SYNOPSIS
Diagnoses and remediates common issues related to Exchange Online In-Place Archiving.

.DESCRIPTION
This script performs a comprehensive health and configuration check on an Exchange Online mailbox
with a focus on In-Place Archive functionality, Managed Folder Assistant (MRM), Retention Policies,
Auto-Expanding Archive, archive provisioning, and basic mailbox health.

The script automatically handles several corrective actions, including:
- Enabling the archive mailbox if disabled
- Enabling Auto-Expanding Archive per user
- Creating Retention Policy Tags and Retention Policies (with configurable retention period)
- Assigning newly created policies to the mailbox
- Triggering the Managed Folder Assistant (MRM)

The script also verifies:
- Presence of the ExchangeOnlineManagement module (and installs it if missing)
- Mailbox existence and connectivity
- Archive mailbox status and provisioning
- Retention Policy validity
- MRM last processing time
- Archive mailbox statistics
- Oldest message in the Inbox folder (language-independent folder detection)

A clear summary is shown at the end of the script, indicating which checks were:
“In order”, “Not in order”, “Missing”, or “Not available”.

.PARAMETER UserPrincipalName
The primary email address (UPN) of the mailbox.
If not provided, the script will prompt for it interactively.

.INPUTS
String (UserPrincipalName)

.OUTPUTS
On-screen diagnostic output, including a final status summary.

.NOTES
Author: (your name)
Requirements: PowerShell 7+, ExchangeOnlineManagement module
Scope: Exchange Online only

.VERSION
1.0
#>

param(
    [string]$UserPrincipalName
)

Write-Host "=== ARCHIVE TROUBLESHOOTING ===" -ForegroundColor Cyan

# ================================================================
# 0. REQUEST EMAIL ADDRESS IF NOT PROVIDED
# ================================================================

if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {
    $UserPrincipalName = Read-Host "No UserPrincipalName provided. Enter the mailbox email address"
}

if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {
    Write-Host "No valid email address provided. Script terminated." -ForegroundColor Red
    exit
}


# ================================================================
# 1. CHECK IF EXCHANGE ONLINE MODULE IS INSTALLED
# ================================================================

Write-Host "[1] Checking for Exchange Online module..." -ForegroundColor Yellow

$exoModule = Get-Module -ListAvailable -Name ExchangeOnlineManagement

if (-not $exoModule) {
    Write-Host "ExchangeOnlineManagement module not found." -ForegroundColor Red
    $install = Read-Host "Install module? (Y/N)"

    if ($install -eq "Y") {
        try {
            Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "Module installed." -ForegroundColor Green
        } catch {
            Write-Host "Failed to install module. Script terminated." -ForegroundColor Red
            exit
        }
    } else {
        Write-Host "Module required. Script terminated." -ForegroundColor Red
        exit
    }
}

if (-not (Get-Module ExchangeOnlineManagement)) {
    try {
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        Write-Host "Module imported." -ForegroundColor Green
    } catch {
        Write-Host "Failed to import ExchangeOnlineManagement." -ForegroundColor Red
        exit
    }
}

if (-not (Get-Command Connect-ExchangeOnline -ErrorAction SilentlyContinue)) {
    Write-Host "Connect-ExchangeOnline command missing. Module installation appears corrupt." -ForegroundColor Red
    exit
}


# ================================================================
# 2. CONNECT TO EXCHANGE ONLINE
# ================================================================

Write-Host "[2] Connecting to Exchange Online..." -ForegroundColor Yellow
try {
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
} catch {}

Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop


# ================================================================
# 3. RETRIEVE MAILBOX
# ================================================================

Write-Host "`n[3] Retrieving mailbox..." -ForegroundColor Yellow
try {
    $mbx = Get-Mailbox -Identity $UserPrincipalName -ErrorAction Stop
    Write-Host "Mailbox found." -ForegroundColor Green
} catch {
    Write-Host "Mailbox not found." -ForegroundColor Red
    exit
}


# ================================================================
# 4. ARCHIVE STATUS
# ================================================================

Write-Host "`n[4] Archive status..." -ForegroundColor Yellow
$archiveEnabled = ($mbx.ArchiveStatus -eq "Active")

if ($archiveEnabled) {
    Write-Host "Archive mailbox is enabled." -ForegroundColor Green
} else {
    Write-Host "Archive mailbox is not enabled." -ForegroundColor Red

    $activate = Read-Host "Enable archive mailbox? (Y/N)"
    if ($activate -eq "Y") {
        Enable-Mailbox -Identity $UserPrincipalName -Archive
        Write-Host "Archive mailbox enabled. Provisioning may take several minutes." -ForegroundColor Green
    }
}


# ================================================================
# 5. AUTO-EXPANDING ARCHIVE
# ================================================================

Write-Host "`n[5] Auto-Expanding Archive..." -ForegroundColor Yellow

$autoExpand = $null
try {
    $autoExpand = (Get-Mailbox -Identity $UserPrincipalName).AutoExpandingArchiveEnabled
} catch {
    $autoExpand = $null
}

if ($autoExpand -eq $true) {
    Write-Host "Auto-Expanding Archive is enabled." -ForegroundColor Green
} elseif ($autoExpand -eq $false) {
    Write-Host "Auto-Expanding Archive is disabled." -ForegroundColor DarkYellow
    $fixAuto = Read-Host "Enable Auto-Expanding Archive? (Y/N)"
    if ($fixAuto -eq "Y") {
        Enable-Mailbox -Identity $UserPrincipalName -AutoExpandingArchive
        Write-Host "Auto-Expanding Archive enabled." -ForegroundColor Green
    }
} else {
    Write-Host "Auto-Expanding Archive status not available in this tenant." -ForegroundColor DarkYellow
}


# ================================================================
# 6. RETENTION POLICY CHECK + OPTIONAL CREATION
# ================================================================

Write-Host "`n[6] Retention Policy..." -ForegroundColor Yellow

$policyName = $mbx.RetentionPolicy
$policy = $null

try {
    $policy = Get-RetentionPolicy -Identity $policyName -ErrorAction Stop
    Write-Host "Retention Policy '$policyName' found." -ForegroundColor Green
} catch {
    Write-Host "Retention Policy '$policyName' missing or invalid." -ForegroundColor Red
}

if (-not $policy) {
    $create = Read-Host "Create a new Retention Policy? (Y/N)"
    if ($create -eq "Y") {

        $daysInput = Read-Host "Retention duration in days (default: 1095)"
        $days = if ([string]::IsNullOrWhiteSpace($daysInput)) { 1095 } else { [int]$daysInput }

        $tagName = "Archive After $days Days"
        $newPolicyName = "MRM Policy - $days Days Archive"

        try {
            $existingTag = Get-RetentionPolicyTag -Identity $tagName -ErrorAction Stop
        } catch {
            New-RetentionPolicyTag -Name $tagName -Type All -RetentionEnabled $true -AgeLimitForRetention $days -RetentionAction MoveToArchive | Out-Null
        }

        try {
            $existingPolicy = Get-RetentionPolicy -Identity $newPolicyName -ErrorAction Stop
        } catch {
            New-RetentionPolicy -Name $newPolicyName -RetentionPolicyTagLinks $tagName | Out-Null
        }

        $assign = Read-Host "Assign this policy to $UserPrincipalName ? (Y/N)"
        if ($assign -eq "Y") {
            Set-Mailbox -Identity $UserPrincipalName -RetentionPolicy $newPolicyName
            Write-Host "Policy assigned." -ForegroundColor Green
            try {
                $policy = Get-RetentionPolicy -Identity $newPolicyName -ErrorAction Stop
            } catch {
                $policy = $null
            }
        }
    }
}


# ================================================================
# 7. MRM STATUS
# ================================================================

Write-Host "`n[7] MRM status..." -ForegroundColor Yellow

$lastMRM = $null
try {
    $mrm = Get-MailboxStatistics $UserPrincipalName | Select LastProcessedTime
    $lastMRM = $mrm.LastProcessedTime
} catch {
    $lastMRM = $null
}

if ($lastMRM) {
    Write-Host "Last MRM processing: $lastMRM" -ForegroundColor Green
} else {
    Write-Host "MRM has not run yet." -ForegroundColor Red
    $runMRM = Read-Host "Run MRM now? (Y/N)"
    if ($runMRM -eq "Y") {
        Start-ManagedFolderAssistant -Identity $UserPrincipalName
        Write-Host "MRM started." -ForegroundColor Green
    }
}


# ================================================================
# 8. ARCHIVE STATISTICS
# ================================================================

Write-Host "`n[8] Archive usage..." -ForegroundColor Yellow
try {
    $stats = Get-MailboxStatistics -Identity $UserPrincipalName -Archive
    $stats | Select DisplayName,TotalItemSize,ItemCount | Format-List
} catch {
    Write-Host "Archive statistics unavailable." -ForegroundColor Red
}


# ================================================================
# 9. OLDEST MAIL IN INBOX – ROBUST, LANGUAGE-INDEPENDENT
# ================================================================

Write-Host "`n[9] Oldest message in Inbox..." -ForegroundColor Yellow
$inboxOldest = $null
$inbox = $null

try {
    $inbox = Get-MailboxFolderStatistics -Identity $UserPrincipalName |
        Where-Object { $_.FolderType -eq "Inbox" }

    if (-not $inbox -or $inbox.Count -eq 0) {
        $inbox = Get-MailboxFolderStatistics -Identity $UserPrincipalName |
            Where-Object {
                $_.FolderPath -match "Inbox" -or
                $_.Name -match "Inbox" -or
                $_.FolderPath -match "Postvak IN" -or
                $_.Name -match "Postvak IN" -or
                $_.FolderPath -match "Boîte de réception" -or
                $_.Name -match "Boîte de réception"
            }
    }

    if ($inbox -and $inbox.ItemsInFolder -gt 0) {
        $inboxOldest = $inbox.OldestItemReceivedDate
        Write-Host "Oldest message in Inbox: $inboxOldest" -ForegroundColor Green

    } elseif ($inbox -and $inbox.ItemsInFolder -eq 0) {
        Write-Host "Inbox is empty." -ForegroundColor DarkYellow

    else {
        Write-Host "Inbox not found. Running fallback scan..." -ForegroundColor DarkYellow

        $allFolders = Get-MailboxFolderStatistics -Identity $UserPrincipalName |
            Where-Object { $_.ItemsInFolder -gt 0 }

        if ($allFolders) {
            $inboxOldest = ($allFolders |
                Sort-Object OldestItemReceivedDate |
                Select-Object -First 1).OldestItemReceivedDate

            Write-Host "Oldest message in mailbox (fallback): $inboxOldest" -ForegroundColor Green
        } else {
            Write-Host "No items found in mailbox." -ForegroundColor Red
        }
    }

} catch {
    Write-Host "Failed to retrieve Inbox information." -ForegroundColor Red
}


# ================================================================
# 10. FINAL SUMMARY
# ================================================================

Write-Host "`n=== SUMMARY ===" -ForegroundColor Magenta

$s1 = if ($archiveEnabled) { "Archive: OK (enabled)" } else { "Archive: Not OK (disabled)" }

if ($autoExpand -eq $true) {
    $s2 = "Auto-Expanding Archive: OK (enabled)"
} elseif ($autoExpand -eq $false) {
    $s2 = "Auto-Expanding Archive: Disabled"
} else {
    $s2 = "Auto-Expanding Archive: Status not available"
}

$s3 = if ($policy) { "Retention Policy: OK ($($policy.Name))" } else { "Retention Policy: Missing or newly created" }
$s4 = if ($lastMRM) { "MRM Processing: OK (last run: $lastMRM)" } else { "MRM Processing: Not OK (never ran)" }
$s5 = if ($inboxOldest) { "Oldest message in Inbox: $inboxOldest" } else { "Oldest message in Inbox: Not available" }

$summary = @($s1, $s2, $s3, $s4, $s5) -join "`n"

Write-Host $summary -ForegroundColor White
Write-Host "`n=== END ===" -ForegroundColor Magenta
