###############################################################
# SHAREPOINT ONLINE VERSION CLEANUP SCRIPT (SPO ONLY, NO PNP)
#
# FEATURES
# --------
# - Automatic version trimming on existing libraries
# - Apply trimming to existing document libraries
# - Trim/delete file versions older than X days
# - Logging
# - Safe by default (Dry Run ON)
#
# REQUIREMENTS
# ------------
# MUST be run in Windows PowerShell 5.1
#
# REQUIRED MODULE:
#   Install-Module Microsoft.Online.SharePoint.PowerShell -Force
#
# SAFE BY DEFAULT:
#   DryRun = $true  -> NO CHANGES MADE
#
# WARNING:
#   This script may delete file versions,
#   but NEVER deletes entire files.
#
###############################################################


###############################################################
# CONFIGURATION
###############################################################

# Tenant short name: Example "contoso"
$TenantName = "yourtenant"

# Admin URL (auto generated)
$adminUrl = "https://$TenantName-admin.sharepoint.com"

# Log file
$logFile = "C:\temp\spo-cleanup.log"

# DRY RUN MODE (true = simulate only)
$DryRun = $true

# Delete file versions older than this number of days
$RetentionDays = 90

# Sites to skip completely
$excludedSites = @(
    "https://$TenantName.sharepoint.com/sites/DoNotTouch",
    "https://$TenantName.sharepoint.com/sites/System",
    "https://$TenantName.sharepoint.com/sites/Records"
)


###############################################################
# LOGGING SETUP
###############################################################

$logDir = Split-Path $logFile
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Log($msg) {
    $entry = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " - " + $msg
    Write-Host $entry
    Add-Content $logFile -Value $entry
}

Log "==== START SPO CLEANUP (DryRun = $DryRun, Tenant = $TenantName) ===="


###############################################################
# PRE-FLIGHT CHECKS
###############################################################

function Fail($msg) {
    Write-Host ""
    Write-Host "[FATAL] $msg" -ForegroundColor Red
    Log "[FATAL] $msg"
    exit 1
}

Log "Running pre-flight checks..."

# Must run in PowerShell 5.1
if ($PSVersionTable.PSVersion.Major -ne 5) {
    Fail "This script must be run in Windows PowerShell 5.1. Current version: $($PSVersionTable.PSVersion)"
}

Log "PowerShell version OK (5.1 detected)"

# Check SPO module
if (-not (Get-Module -ListAvailable -Name Microsoft.Online.SharePoint.PowerShell)) {
    Fail "Microsoft.Online.SharePoint.PowerShell module missing. Install with: Install-Module Microsoft.Online.SharePoint.PowerShell -Force"
}

Log "SPO module found"

# Check required cmdlets
$requiredCmdlets = @(
    "Connect-SPOService",
    "Get-SPOSite",
    "Set-SPOSite",
    "New-SPOSiteFileVersionBatchDeleteJob"
)

foreach ($cmd in $requiredCmdlets) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Fail "Missing required cmdlet: $cmd"
    }
}

Log "All required SPO cmdlets available"

Log "Pre-flight checks completed successfully."


###############################################################
# CONNECT TO SPO ADMIN
###############################################################

Log "Connecting to SharePoint Online Admin..."
Connect-SPOService -Url $adminUrl


###############################################################
# RETRIEVE ALL SITES
###############################################################

Log "Retrieving all site collections..."
$sites = Get-SPOSite -Limit All


###############################################################
# MAIN PROCESSING LOOP
###############################################################

foreach ($site in $sites) {

    # Exclusions
    if ($excludedSites -contains $site.Url) {
        Log ("SKIPPED SITE: " + $site.Url)
        continue
    }

    Log ("Processing site: " + $site.Url)


    ###############################################################
    # APPLY AUTOMATIC TRIMMING
    ###############################################################
    if ($DryRun) {
        Log "DRY RUN: Would enable Automatic trimming for this site"
    } else {
        try {
            Set-SPOSite -Identity $site.Url `
                -EnableAutoExpirationVersionTrim $true `
                -ApplyToExistingDocumentLibraries `
                -Confirm:$false

            Log "Automatic trimming applied"
        }
        catch {
            Log ("ERROR applying automatic trimming: " + $_)
        }
    }


    ###############################################################
    # RUN VERSION CLEANUP JOB (OLDER THAN X DAYS)
    ###############################################################
    if ($DryRun) {
        Log ("DRY RUN: Would delete versions older than " + $RetentionDays + " days")
    } else {
        try {
            New-SPOSiteFileVersionBatchDeleteJob -Identity $site.Url `
                -Days $RetentionDays `
                -Confirm:$false

            Log ("Cleanup job started (" + $RetentionDays + " days)")
        }
        catch {
            Log ("ERROR starting cleanup job: " + $_)
        }
    }
}

Log ("==== SPO CLEANUP COMPLETED (DryRun = " + $DryRun + ") ====")
