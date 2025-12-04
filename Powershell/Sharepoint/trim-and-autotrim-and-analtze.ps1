###############################################################
# SHAREPOINT ONLINE VERSION TOOL (SPO ONLY, NO PNP)
#
# MODES
# -----
# 1) Cleanup
#    - Automatic version trimming enablen op sites
#    - Trim job starten voor versies ouder dan X dagen
#
# 2) Analyze
#    - CSV version usage reports inlezen (New-SPOSiteFileVersionExpirationReportJob)
#    - HTML rapport genereren per site (aantal versies, grootte, potentieel te winnen ruimte)
#
# REQUIREMENTS
# ------------
# - Windows PowerShell 5.1
# - Module: Microsoft.Online.SharePoint.PowerShell
#
###############################################################

###############################################################
# GLOBAL CONFIG
###############################################################

# Mode: "Cleanup" of "Analyze"
$Mode = "Cleanup"   # Pas aan naar "Analyze" voor HTML analyse

# Tenant short name: Example "contoso"
$TenantName = "yourtenant"

# Admin URL (auto gegenereerd)
$adminUrl = "https://$TenantName-admin.sharepoint.com"

# Log file (voor beide modes hergebruikt)
$logFile = "C:\temp\spo-version-tool.log"

# Cleanup settings
$DryRun        = $true    # Alleen voor Mode = Cleanup relevant
$RetentionDays = 90       # Zowel voor Cleanup als Analyze (cutoff)

# Sites te skippen in Cleanup
$excludedSites = @(
    "https://$TenantName.sharepoint.com/sites/DoNotTouch",
    "https://$TenantName.sharepoint.com/sites/System",
    "https://$TenantName.sharepoint.com/sites/Records"
)

# Analyze settings (CSV inlezen en HTML genereren)
$ReportFolder   = "C:\temp\spo-reports"              # Map met CSV's van New-SPOSiteFileVersionExpirationReportJob
$HtmlReportPath = "C:\temp\spo-version-analysis.html"


###############################################################
# LOGGING SETUP
###############################################################

$logDir = Split-Path $logFile
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Log {
    param(
        [string]$Message
    )
    $entry = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " - " + $Message
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}


###############################################################
# COMMON: FATAL HELPER
###############################################################

function Fail {
    param(
        [string]$Message
    )
    Write-Host ""
    Write-Host "[FATAL] $Message" -ForegroundColor Red
    Log "[FATAL] $Message"
    exit 1
}


###############################################################
# MODE: CLEANUP
###############################################################

function Run-Cleanup {

    Log "=== MODE: CLEANUP (DryRun = $DryRun, Tenant = $TenantName) ==="

    # PRE-FLIGHT CHECKS
    Log "Running pre-flight checks for Cleanup..."

    if ($PSVersionTable.PSVersion.Major -ne 5) {
        Fail "This script must be run in Windows PowerShell 5.1. Current version: $($PSVersionTable.PSVersion)"
    }

    Log "PowerShell version OK (5.1 detected)"

    if (-not (Get-Module -ListAvailable -Name Microsoft.Online.SharePoint.PowerShell)) {
        Fail "Microsoft.Online.SharePoint.PowerShell module missing. Install with: Install-Module Microsoft.Online.SharePoint.PowerShell -Force"
    }

    Log "SPO module found"

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
    Log "Pre-flight checks for Cleanup completed successfully."

    # CONNECT TO ADMIN
    Log "Connecting to SharePoint Online Admin..."
    Connect-SPOService -Url $adminUrl

    # GET SITES
    Log "Retrieving all site collections..."
    $sites = Get-SPOSite -Limit All

    $cutoffInfo = "Versions older than $RetentionDays days will be targeted (if DryRun = False)."
    Log $cutoffInfo

    foreach ($site in $sites) {

        if ($excludedSites -contains $site.Url) {
            Log ("SKIPPED SITE: " + $site.Url)
            continue
        }

        Log ("Processing site: " + $site.Url)

        # 1) Automatic trimming aanzetten
        if ($DryRun) {
            Log "DRY RUN: Would enable Automatic trimming for this site (ApplyToExistingDocumentLibraries)"
        }
        else {
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

        # 2) Cleanup job starten
        if ($DryRun) {
            Log ("DRY RUN: Would start cleanup job (versions older than " + $RetentionDays + " days)")
        }
        else {
            try {
                New-SPOSiteFileVersionBatchDeleteJob -Identity $site.Url `
                    -DeleteBeforeDays $RetentionDays `
                    -Confirm:$false

                Log ("Cleanup job started (DeleteBeforeDays = " + $RetentionDays + ")")
            }
            catch {
                Log ("ERROR starting cleanup job: " + $_)
            }
        }
    }

    Log ("=== CLEANUP COMPLETED (DryRun = " + $DryRun + ") ===")
}


###############################################################
# MODE: ANALYZE (HTML REPORT)
###############################################################

function Run-Analyze {

    Log "=== MODE: ANALYZE (Tenant = $TenantName) ==="
    Log ("Using ReportFolder = " + $ReportFolder)
    Log ("Using HtmlReportPath = " + $HtmlReportPath)
    Log ("RetentionDays (for 'older than' metric) = " + $RetentionDays)

    if (!(Test-Path $ReportFolder)) {
        Fail "ReportFolder '$ReportFolder' does not exist. Place CSV files from New-SPOSiteFileVersionExpirationReportJob there."
    }

    $csvFiles = Get-ChildItem -Path $ReportFolder -Filter *.csv
    if (-not $csvFiles -or $csvFiles.Count -eq 0) {
        Fail "No CSV files found in '$ReportFolder'."
    }

    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)

    $siteSummaries = New-Object System.Collections.Generic.List[System.Object]

    foreach ($file in $csvFiles) {
        Log ("Analyzing CSV: " + $file.FullName)

        try {
            $rows = Import-Csv -Path $file.FullName
        }
        catch {
            Log ("ERROR reading CSV " + $file.FullName + ": " + $_)
            continue
        }

        if (-not $rows -or $rows.Count -eq 0) {
            Log ("No rows found in CSV: " + $file.FullName)
            continue
        }

        # Probeer SiteUrl kolom te vinden
        $siteUrl = $null
        foreach ($candidate in @("SiteUrl","SiteURL","Site")) {
            if ($rows[0].PSObject.Properties.Name -contains $candidate) {
                $siteUrl = $rows[0].$candidate
                break
            }
        }
        if (-not $siteUrl) {
            $siteUrl = "Unknown (from " + $file.Name + ")"
        }

        $totalVersions = $rows.Count

        # Probeer versie-datum en grootte te lezen
        $dateColumn = $null
        foreach ($candidate in @("VersionCreated","LastModified","ModifiedTime")) {
            if ($rows[0].PSObject.Properties.Name -contains $candidate) {
                $dateColumn = $candidate
                break
            }
        }

        $sizeColumn = $null
        foreach ($candidate in @("VersionSize","Size","SizeInBytes")) {
            if ($rows[0].PSObject.Properties.Name -contains $candidate) {
                $sizeColumn = $candidate
                break
            }
        }

        $olderCount = 0
        [double]$totalSizeBytes = 0
        [double]$olderSizeBytes = 0

        foreach ($row in $rows) {
            if ($sizeColumn -and $row.$sizeColumn) {
                [double]$bytes = 0
                [double]::TryParse($row.$sizeColumn, [ref]$bytes) | Out-Null
                $totalSizeBytes += $bytes
            }

            if ($dateColumn -and $row.$dateColumn) {
                [datetime]$verDate = $null
                [datetime]::TryParse($row.$dateColumn, [ref]$verDate) | Out-Null

                if ($verDate -lt $cutoffDate) {
                    $olderCount++
                    if ($sizeColumn -and $row.$sizeColumn) {
                        [double]$bytesOld = 0
                        [double]::TryParse($row.$sizeColumn, [ref]$bytesOld) | Out-Null
                        $olderSizeBytes += $bytesOld
                    }
                }
            }
        }

        $totalMB = [math]::Round($totalSizeBytes / 1MB, 2)
        $totalGB = [math]::Round($totalSizeBytes / 1GB, 2)

        $olderMB = [math]::Round($olderSizeBytes / 1MB, 2)
        $olderGB = [math]::Round($olderSizeBytes / 1GB, 2)

        $summary = [PSCustomObject]@{
            SiteUrl              = $siteUrl
            CsvFile              = $file.Name
            TotalVersions        = $totalVersions
            VersionsOlderThanX   = $olderCount
            TotalSizeMB          = $totalMB
            TotalSizeGB          = $totalGB
            OlderSizeMB          = $olderMB
            OlderSizeGB          = $olderGB
        }

        $siteSummaries.Add($summary) | Out-Null
    }

    if ($siteSummaries.Count -eq 0) {
        Fail "No usable data found in CSV files. Check column names or report format."
    }

    # HTML genereren
    $htmlDir = Split-Path $HtmlReportPath
    if (!(Test-Path $htmlDir)) {
        New-Item -ItemType Directory -Path $htmlDir -Force | Out-Null
    }

    $css = @"
<style>
    body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
        background: #f5f7fb;
        margin: 0;
        padding: 0;
        color: #222;
    }
    .container {
        max-width: 1200px;
        margin: 30px auto;
        background: #ffffff;
        border-radius: 8px;
        box-shadow: 0 10px 30px rgba(0,0,0,0.05);
        padding: 24px 32px 32px 32px;
    }
    h1 {
        margin-top: 0;
        font-size: 26px;
        color: #1f3b57;
    }
    .meta {
        font-size: 13px;
        color: #666;
        margin-bottom: 20px;
    }
    table {
        width: 100%;
        border-collapse: collapse;
        margin-top: 15px;
        font-size: 13px;
    }
    thead {
        background: linear-gradient(90deg, #304ffe, #00b0ff);
        color: white;
    }
    th, td {
        padding: 8px 10px;
        text-align: left;
        border-bottom: 1px solid #e2e5ee;
    }
    tr:nth-child(even) {
        background-color: #f9fafc;
    }
    tr:hover {
        background-color: #eef3ff;
    }
    th {
        font-weight: 600;
        white-space: nowrap;
    }
    .number {
        text-align: right;
        font-variant-numeric: tabular-nums;
    }
    .pill {
        display: inline-block;
        padding: 2px 8px;
        border-radius: 999px;
        font-size: 11px;
        background: #e3f2fd;
        color: #1565c0;
    }
    .pill-high {
        background: #ffebee;
        color: #c62828;
    }
    .footer {
        margin-top: 20px;
        font-size: 12px;
        color: #888;
    }
</style>
"@

    $htmlHead = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>SharePoint Version Analysis - $TenantName</title>
$css
</head>
<body>
<div class="container">
<h1>SharePoint Version Analysis</h1>
<div class="meta">
    Tenant: <strong>$TenantName</strong><br/>
    Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")<br/>
    Cutoff for "older than" metrics: Versions older than $RetentionDays days
</div>
<table>
    <thead>
        <tr>
            <th>Site URL</th>
            <th>CSV File</th>
            <th class="number">Total Versions</th>
            <th class="number">Versions &gt; $RetentionDays days</th>
            <th class="number">Total Size (MB)</th>
            <th class="number">Total Size (GB)</th>
            <th class="number">Older Size (MB)</th>
            <th class="number">Older Size (GB)</th>
        </tr>
    </thead>
    <tbody>
"@

    $rowsHtml = ""

    foreach ($s in $siteSummaries) {

        $olderClass = ""
        if ($s.OlderSizeGB -ge 1) {
            $olderClass = "pill pill-high"
        } elseif ($s.OlderSizeGB -gt 0) {
            $olderClass = "pill"
        }

        $olderDisplay = ""
        if ($s.OlderSizeGB -gt 0) {
            $olderDisplay = "<span class=""$olderClass"">" + $s.OlderSizeGB + " GB</span>"
        }
        else {
            $olderDisplay = $s.OlderSizeGB
        }

        $rowsHtml += @"
        <tr>
            <td>$($s.SiteUrl)</td>
            <td>$($s.CsvFile)</td>
            <td class="number">$($s.TotalVersions)</td>
            <td class="number">$($s.VersionsOlderThanX)</td>
            <td class="number">$($s.TotalSizeMB)</td>
            <td class="number">$($s.TotalSizeGB)</td>
            <td class="number">$($s.OlderSizeMB)</td>
            <td class="number">$olderDisplay</td>
        </tr>
"@
    }

    $htmlFooter = @"
    </tbody>
</table>
<div class="footer">
    Data source: CSV version usage reports generated with New-SPOSiteFileVersionExpirationReportJob.<br/>
    Note: Actual cleanup impact may be lower if retention policies or holds are in effect.
</div>
</div>
</body>
</html>
"@

    $fullHtml = $htmlHead + $rowsHtml + $htmlFooter
    Set-Content -Path $HtmlReportPath -Value $fullHtml -Encoding UTF8

    Log ("HTML report generated at: " + $HtmlReportPath)
    Log "=== ANALYZE COMPLETED ==="
}


###############################################################
# MAIN DISPATCH
###############################################################

if ($Mode -eq "Cleanup") {
    Run-Cleanup
}
elseif ($Mode -eq "Analyze") {
    Run-Analyze
}
else {
    Fail "Unknown Mode '$Mode'. Use 'Cleanup' or 'Analyze'."
}
