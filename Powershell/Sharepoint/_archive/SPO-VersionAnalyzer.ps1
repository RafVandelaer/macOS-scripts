###############################################################
# SHAREPOINT ONLINE VERSION ANALYZER
#
# Connects directly to SharePoint Online and analyzes version data
# Generates HTML report with version statistics per site
#
# REQUIREMENTS
# - Windows PowerShell 5.1
# - Module: Microsoft.Online.SharePoint.PowerShell
# - Module: PnP.PowerShell
#
# USAGE
# - Interactive (default): .\SPO-VersionAnalyzer.ps1
# - Non-interactive: .\SPO-VersionAnalyzer.ps1 -NonInteractive
#
###############################################################

param(
    [switch]$NonInteractive
)

# Interactive is default, unless -NonInteractive is specified
$Interactive = -not $NonInteractive

###############################################################
# GLOBAL CONFIG
###############################################################

# Tenant short name: Example "contoso"
$TenantName = "yourtenant"

# Admin URL
$adminUrl = "https://$TenantName-admin.sharepoint.com"

# Detect OS and set appropriate temp directory
if ($PSVersionTable.Platform -eq "Unix" -or $PSVersionTable.OS -like "*Darwin*") {
    $tempDir = "/tmp"
} else {
    $tempDir = "C:\temp"
}

# Log file
$logFile = Join-Path $tempDir "spo-version-analyzer.log"

# Analysis settings
$RetentionDays = 90
$HtmlReportPath = Join-Path $tempDir "spo-version-analysis.html"


###############################################################
# LOGGING SETUP
###############################################################

$logDir = Split-Path $logFile
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Log {
    param([string]$Message)
    $entry = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " - " + $Message
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}

###############################################################
# COMMON: FATAL HELPER
###############################################################

function Fail {
    param([string]$Message)
    Write-Host ""
    Write-Host "[FATAL] $Message" -ForegroundColor Red
    Log "[FATAL] $Message"
    exit 1
}

###############################################################
# INTERACTIVE SETUP
###############################################################

if ($Interactive) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  SHAREPOINT VERSION ANALYZER" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    Write-Host "Press Enter to accept the default value [in brackets].`n" -ForegroundColor Yellow
    Write-Host "HINT: Find tenant name in SharePoint Admin URL:" -ForegroundColor Green
    Write-Host "      https://[TENANT-NAME]-admin.sharepoint.com" -ForegroundColor Green
    Write-Host "      Example: https://contoso-admin.sharepoint.com -> enter: contoso`n" -ForegroundColor Green

    # Tenant name
    $tenantInput = Read-Host "Tenant name (see hint above) [$TenantName]"
    if (-not [string]::IsNullOrWhiteSpace($tenantInput)) {
        $TenantName = $tenantInput.Trim()
        $adminUrl = "https://$TenantName-admin.sharepoint.com"
    }

    # Retention days
    $retInput = Read-Host "Retention days (older than X days) [$RetentionDays]"
    if (-not [string]::IsNullOrWhiteSpace($retInput)) {
        if ([int]::TryParse($retInput, [ref]$null)) {
            $RetentionDays = [int]$retInput
        }
        else {
            Write-Host "Invalid input, using default $RetentionDays" -ForegroundColor Yellow
        }
    }

    # HTML output path
    $htmlInput = Read-Host "HTML output file [$HtmlReportPath]"
    if (-not [string]::IsNullOrWhiteSpace($htmlInput)) {
        $HtmlReportPath = $htmlInput.Trim()
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  CONFIGURATION" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Tenant         : $TenantName"
    Write-Host "Admin URL      : $adminUrl"
    Write-Host "RetentionDays  : $RetentionDays"
    Write-Host "HtmlReportPath : $HtmlReportPath"
    Write-Host "========================================`n" -ForegroundColor Cyan

    $proceed = Read-Host "Continue with this configuration? (Y/n)"
    if ($proceed.ToLower() -eq "n") {
        Write-Host "Cancelled by user." -ForegroundColor Yellow
        exit 0
    }
}

###############################################################
# ANALYSIS FUNCTION
###############################################################

function Analyze-SharePointVersions {

    Log "=== SHAREPOINT VERSION ANALYSIS STARTED ===" 
    Log ("Tenant: " + $TenantName)
    Log ("RetentionDays: " + $RetentionDays)

    # PRE-FLIGHT CHECKS
    Log "Running pre-flight checks..."

    if ($PSVersionTable.PSVersion.Major -ne 5) {
        Fail "This script must be run in Windows PowerShell 5.1. Current version: $($PSVersionTable.PSVersion)"
    }
    Log "PowerShell version OK (5.1 detected)"

    if (-not (Get-Module -ListAvailable -Name Microsoft.Online.SharePoint.PowerShell)) {
        Fail "Microsoft.Online.SharePoint.PowerShell module missing. Install with: Install-Module Microsoft.Online.SharePoint.PowerShell -Force"
    }
    Log "SPO module found"

    if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
        Write-Host "PnP.PowerShell module not found. Installing..." -ForegroundColor Yellow
        try {
            Install-Module PnP.PowerShell -Force -Scope CurrentUser -AllowClobber
            Log "PnP.PowerShell installed successfully"
        }
        catch {
            Fail "Failed to install PnP.PowerShell: $_"
        }
    }
    Log "PnP.PowerShell module found"

    # CONNECT TO ADMIN
    Log "Connecting to SharePoint Online Admin..."
    try {
        Connect-SPOService -Url $adminUrl -ErrorAction Stop
    }
    catch {
        Fail "Failed to connect to SharePoint Admin: $_"
    }
    Log "Connected to Admin successfully"

    # GET SITES
    Log "Retrieving all site collections..."
    try {
        $sites = Get-SPOSite -Limit All -ErrorAction Stop
    }
    catch {
        Fail "Failed to retrieve sites: $_"
    }
    Log ("Total sites found: " + $sites.Count)

    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $siteSummaries = @()

    # ANALYZE EACH SITE
    foreach ($site in $sites) {
        $siteIndex = ($sites.IndexOf($site) + 1)
        Log ("[" + $siteIndex + "/" + $sites.Count + "] Analyzing: " + $site.Url)

        $totalVersions = 0
        $olderCount = 0
        $totalSizeBytes = 0
        $olderSizeBytes = 0

        try {
            # Connect to site with PnP
            Connect-PnPOnline -Url $site.Url -Interactive -ErrorAction SilentlyContinue
            
            if ($?) {
                # Get all document libraries
                $lists = Get-PnPList -Includes BaseType, ItemCount -ErrorAction SilentlyContinue
                
                foreach ($list in $lists) {
                    if ($list.BaseType -eq "DocumentLibrary" -and $list.ItemCount -gt 0) {
                        Log ("  Scanning library: " + $list.Title + " (" + $list.ItemCount + " items)")
                        
                        try {
                            $items = Get-PnPListItem -List $list.Id -PageSize 5000 -ErrorAction SilentlyContinue
                            
                            foreach ($item in $items) {
                                if ($item["FileLeafRef"]) {
                                    try {
                                        $versions = Get-PnPFileVersion -Url $item["FileRef"] -ErrorAction SilentlyContinue
                                        
                                        foreach ($version in $versions) {
                                            $totalVersions++
                                            
                                            # Get version size
                                            $versionSize = 0
                                            if ($version.PSObject.Properties["Size"]) {
                                                [double]::TryParse($version.Size, [ref]$versionSize) | Out-Null
                                            }
                                            $totalSizeBytes += $versionSize
                                            
                                            # Check if version is older than retention days
                                            $versionDate = [datetime]::MinValue
                                            if ($version.PSObject.Properties["Created"]) {
                                                [datetime]::TryParse($version.Created, [ref]$versionDate) | Out-Null
                                            }
                                            
                                            if ($versionDate -lt $cutoffDate) {
                                                $olderCount++
                                                $olderSizeBytes += $versionSize
                                            }
                                        }
                                    }
                                    catch {
                                        # Continue on individual file errors
                                    }
                                }
                            }
                        }
                        catch {
                            Log ("  Warning: Could not process library $($list.Title): " + $_.Exception.Message)
                        }
                    }
                }
            }
            
            Disconnect-PnPOnline -ErrorAction SilentlyContinue
        }
        catch {
            Log ("  Note: Could not access site details: " + $_.Exception.Message)
        }

        # Add to summary if any versions found
        if ($totalVersions -gt 0) {
            $totalMB = [math]::Round($totalSizeBytes / 1MB, 2)
            $totalGB = [math]::Round($totalSizeBytes / 1GB, 2)
            $olderMB = [math]::Round($olderSizeBytes / 1MB, 2)
            $olderGB = [math]::Round($olderSizeBytes / 1GB, 2)

            Log ("  Found: " + $totalVersions + " versions, " + $totalGB + " GB (Older: " + $olderCount + " versions, " + $olderGB + " GB)")

            $summary = [PSCustomObject]@{
                SiteUrl              = $site.Url
                SiteTitle            = $site.Title
                TotalVersions        = $totalVersions
                VersionsOlderThanX   = $olderCount
                TotalSizeMB          = $totalMB
                TotalSizeGB          = $totalGB
                OlderSizeMB          = $olderMB
                OlderSizeGB          = $olderGB
            }
            $siteSummaries += $summary
        }
    }

    Log ("Analysis complete. Found " + $siteSummaries.Count + " sites with version data.")

    # GENERATE HTML REPORT
    if ($siteSummaries.Count -gt 0) {
        Log "Generating HTML report..."
        
        $htmlDir = Split-Path $HtmlReportPath
        if ($htmlDir -and !(Test-Path $htmlDir)) {
            try {
                New-Item -ItemType Directory -Path $htmlDir -Force -ErrorAction Stop | Out-Null
                Log ("Created directory: " + $htmlDir)
            }
            catch {
                Fail "Failed to create HTML directory '$htmlDir': $_"
            }
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
    Cutoff for "older than" metrics: Versions older than $RetentionDays days<br/>
    Total sites analyzed: <strong>$($siteSummaries.Count)</strong>
</div>
<table>
    <thead>
        <tr>
            <th>Site URL</th>
            <th>Site Title</th>
            <th class="number">Total Versions</th>
            <th class="number">Versions &gt; $RetentionDays days</th>
            <th class="number">Total Size (GB)</th>
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

            $olderDisplay = if ($s.OlderSizeGB -gt 0) {
                "<span class=""$olderClass"">" + $s.OlderSizeGB + " GB</span>"
            } else {
                $s.OlderSizeGB
            }

            $rowsHtml += @"
        <tr>
            <td>$($s.SiteUrl)</td>
            <td>$($s.SiteTitle)</td>
            <td class="number">$($s.TotalVersions)</td>
            <td class="number">$($s.VersionsOlderThanX)</td>
            <td class="number">$($s.TotalSizeGB)</td>
            <td class="number">$olderDisplay</td>
        </tr>
"@
        }

        $htmlFooter = @"
    </tbody>
</table>
<div class="footer">
    Report generated at $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")<br/>
    Note: Actual cleanup impact may be lower if retention policies or holds are in effect.
</div>
</div>
</body>
</html>
"@

        $fullHtml = $htmlHead + $rowsHtml + $htmlFooter
        
        try {
            Set-Content -Path $HtmlReportPath -Value $fullHtml -Encoding UTF8 -ErrorAction Stop
            $htmlFile = Get-Item $HtmlReportPath
            Log ("HTML report written: " + $HtmlReportPath)
            Log ("File size: " + [math]::Round($htmlFile.Length / 1KB, 2) + " KB")
        }
        catch {
            Fail "Failed to write HTML report to '$HtmlReportPath': $_"
        }
    }
    else {
        Log "No sites with version data found."
    }

    Log "=== ANALYSIS COMPLETED ==="
}

###############################################################
# MAIN
###############################################################

Analyze-SharePointVersions
