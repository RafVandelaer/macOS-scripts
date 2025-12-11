###############################################################
# SHAREPOINT ONLINE VERSION TOOL
#
# MODES
# -----
# 1) Cleanup
#    - Enable automatic version trimming on sites
#    - Start trim job for versions older than X days
#
# 2) Analyze  
#    - Connect to SharePoint Online directly
#    - Analyze storage usage from all sites
#    - Generate HTML report
#
# REQUIREMENTS
# - Windows PowerShell 5.1
# - Module: Microsoft.Online.SharePoint.PowerShell
#
# USAGE
# - Interactive: .\SPO-VersionCleanupAndAnalysis.ps1
# - Non-interactive: .\SPO-VersionCleanupAndAnalysis.ps1 -NonInteractive
#
###############################################################

param(
    [switch]$NonInteractive,
    [switch]$LoadConfigFromFile,
    [string]$ConfigPath
)

$Interactive = -not $NonInteractive

###############################################################
# GLOBAL CONFIG
###############################################################

$Mode = "Cleanup"
$TenantName = "yourtenant"
$adminUrl = "https://$TenantName-admin.sharepoint.com"

if ($PSVersionTable.Platform -eq "Unix" -or $PSVersionTable.OS -like "*Darwin*") {
    $tempDir = "/tmp"
} else {
    $tempDir = "C:\temp"
}

$logFile = Join-Path $tempDir "spo-version-tool.log"
$DryRun = $true
$RetentionDays = 90
$HtmlReportPath = Join-Path $tempDir "spo-version-analysis.html"
$versionStrategy = "manual"

$excludedSites = @()

###############################################################
# LOGGING
###############################################################

$logDir = Split-Path $logFile
if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Get-ConfigPath {
    param([string]$Tenant)
    if ([string]::IsNullOrWhiteSpace($Tenant) -or $Tenant -eq "yourtenant") {
        return Join-Path $tempDir "spo-version-tool-config.json"
    }
    return Join-Path $tempDir "spo-version-tool-config-$Tenant.json"
}

# Allow overriding config path via parameter; otherwise derive from tenant
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $configFile = Get-ConfigPath $TenantName
    $configLoaded = $false
} else {
    $configFile = $ConfigPath
}

function Log {
    param([string]$Message)
    $entry = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + " - " + $Message
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}

function Fail {
    param([string]$Message)
    Write-Host ""
    Write-Host "[FATAL] $Message" -ForegroundColor Red
    Log "[FATAL] $Message"
    exit 1
}

function Save-Config {
    param([string]$Path)
    $config = @{
        TenantName = $TenantName
        Mode = $Mode
        RetentionDays = $RetentionDays
        versionStrategy = $versionStrategy
        excludedSites = $excludedSites
        DryRun = $DryRun
    }
    $config | ConvertTo-Json | Set-Content -Path $Path -Encoding UTF8
    Write-Host "`nConfig saved successfully!" -ForegroundColor Green
    Write-Host "  Location: $Path" -ForegroundColor Green
    Write-Host "  Tenant:   $TenantName" -ForegroundColor Green
    Log "Config saved to: $Path"
}

function Load-Config {
    param([string]$Path)
    if (Test-Path $Path) {
        try {
            $config = Get-Content -Path $Path -Encoding UTF8 | ConvertFrom-Json
            $script:TenantName = $config.TenantName
            $script:Mode = $config.Mode
            $script:RetentionDays = $config.RetentionDays
            $script:versionStrategy = $config.versionStrategy
            $script:excludedSites = @($config.excludedSites)
            if ($config.PSObject.Properties.Name -contains 'DryRun') {
                $script:DryRun = [bool]$config.DryRun
            }
            $script:configLoaded = $true
            Log "Config loaded from: $Path"
            return $true
        }
        catch {
            Write-Host "Failed to load config: $_" -ForegroundColor Yellow
            return $false
        }
    }
    return $false
}

# Auto-load config when requested (useful for -NonInteractive runs)
if ($LoadConfigFromFile) {
    if (-not (Load-Config $configFile)) {
        Fail "Failed to load config from: $configFile"
    }

    # Update dependent values when tenant changes via config
    $adminUrl = "https://$TenantName-admin.sharepoint.com"

    # If config path was not explicitly provided, realign to tenant-specific default
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $configFile = Get-ConfigPath $TenantName
    }
}

###############################################################
# INTERACTIVE SETUP
###############################################################

if ($Interactive) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  SHAREPOINT VERSION TOOL - INTERACTIVE" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $configPreloaded = $false
    $configLoaded = $configLoaded -or $false

    # Offer any existing configs in temp dir (helps when tenant-specific file exists)
    $availableConfigs = Get-ChildItem -Path $tempDir -Filter "spo-version-tool-config*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($availableConfigs.Count -gt 0) {
        Write-Host "Found existing config files:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $availableConfigs.Count; $i++) {
            $item = $availableConfigs[$i]
            Write-Host "  [$($i+1)] $($item.Name) (last modified: $($item.LastWriteTime))" -ForegroundColor Gray
        }
        $pick = Read-Host "Select a config to load by number, or press Enter to skip"
        if ([int]::TryParse($pick, [ref]$null) -and $pick -ge 1 -and $pick -le $availableConfigs.Count) {
            $selectedConfig = $availableConfigs[$pick - 1].FullName
            if (Load-Config $selectedConfig) {
                $configPreloaded = $true
                $configFile = $selectedConfig
                $adminUrl = "https://$TenantName-admin.sharepoint.com"
                Write-Host "Config loaded from: $selectedConfig" -ForegroundColor Green
            }
        }
    }

    # Try to load previous config (default path) if not already loaded
    Write-Host "Config location: $configFile" -ForegroundColor Gray
    if ((-not $configPreloaded) -and (Test-Path $configFile)) {
        $lastWrite = (Get-Item $configFile).LastWriteTime
        Write-Host "Found existing config (last modified: $lastWrite)." -ForegroundColor Yellow
        $loadPrev = Read-Host "`nLoad previous config now? (y/N) [N]"
        if ($loadPrev.ToLower() -eq "y") {
            if (Load-Config $configFile) {
                Write-Host "Previous config loaded successfully from: $configFile" -ForegroundColor Green
                $configLoaded = $true
            }
        }
    }
    
    Write-Host "`nPress Enter to accept the default value [in brackets].`n" -ForegroundColor Yellow
    Write-Host "HINT: Find tenant name in SharePoint Admin URL:" -ForegroundColor Green
    Write-Host "      https://[TENANT-NAME]-admin.sharepoint.com" -ForegroundColor Green
    Write-Host "      Example: https://contoso-admin.sharepoint.com -> enter: contoso`n" -ForegroundColor Green

    # Mode selection (supports C/Cleanup or A/Analyze)
    $modeInput = Read-Host "Mode (C=Cleanup, A=Analyze) [$Mode]"
    if (-not [string]::IsNullOrWhiteSpace($modeInput)) {
        $modeInput = $modeInput.Trim().ToUpper()
        
        if ($modeInput -eq "C" -or $modeInput -eq "CLEANUP") {
            $Mode = "Cleanup"
        }
        elseif ($modeInput -eq "A" -or $modeInput -eq "ANALYZE") {
            $Mode = "Analyze"
        }
        else {
            Write-Host "Invalid mode '$modeInput'. Use C/Cleanup or A/Analyze." -ForegroundColor Red
            $proceed = Read-Host "Use Analyze mode instead? (Y/n)"
            if ($proceed.ToLower() -ne "n") {
                $Mode = "Analyze"
                Write-Host "Using: Analyze" -ForegroundColor Green
            } else {
                $Mode = "Cleanup"
                Write-Host "Using: Cleanup" -ForegroundColor Green
            }
        }
    }

    # If a config is loaded, offer to skip all other prompts
    $skipConfigPrompts = $false
    if ($configLoaded) {
        $skipInput = Read-Host "`nConfig loaded. Keep loaded tenant/settings and skip remaining prompts? (Y/n) [Y]"
        if ([string]::IsNullOrWhiteSpace($skipInput) -or $skipInput.Trim().ToLower() -eq "y") {
            $skipConfigPrompts = $true
        }
    }

    if (-not $skipConfigPrompts) {
        # Tenant name
        $tenantInput = Read-Host "Tenant name (see hint above) [$TenantName]"
        if (-not [string]::IsNullOrWhiteSpace($tenantInput)) {
            $TenantName = $tenantInput.Trim()
            $adminUrl = "https://$TenantName-admin.sharepoint.com"
            $configFile = Get-ConfigPath $TenantName
        }

        if ($Mode -eq "Cleanup") {
            Write-Host "`n--- Version Management Strategy ---" -ForegroundColor Cyan
            Write-Host "How should SharePoint manage old versions?" -ForegroundColor Yellow
            Write-Host "  1. Manual: Set specific retention days (keep X days)" -ForegroundColor Gray
            Write-Host "  2. Auto: Let Microsoft handle it (30 days default)" -ForegroundColor Gray
            Write-Host "  3. None: Don't change current settings" -ForegroundColor Gray
            
            $strategyInput = Read-Host "Choose strategy (1-3) [1]"
            $versionStrategy = "manual"
            
            if ($strategyInput -eq "2") {
                $versionStrategy = "auto"
                Write-Host "Using Microsoft auto-management (30 days)" -ForegroundColor Green
            }
            elseif ($strategyInput -eq "3") {
                $versionStrategy = "none"
                Write-Host "No changes will be made to version settings" -ForegroundColor Yellow
            }
            else {
                $versionStrategy = "manual"
                Write-Host "Using manual retention strategy" -ForegroundColor Green
            }

            # Retention days - AFTER strategy selection
            if ($versionStrategy -ne "none") {
                $retInput = Read-Host "`nRetention days (older than X days) [$RetentionDays]"
                if (-not [string]::IsNullOrWhiteSpace($retInput)) {
                    if ([int]::TryParse($retInput, [ref]$null)) {
                        $RetentionDays = [int]$retInput
                    }
                    else {
                        Write-Host "Invalid input, using default $RetentionDays" -ForegroundColor Yellow
                    }
                }
            }

            $dryInput = Read-Host "`nDry run? (Y/n) [Y]"
            if ([string]::IsNullOrWhiteSpace($dryInput) -or $dryInput.Trim().ToLower() -eq "y") {
                $DryRun = $true
            }
            elseif ($dryInput.Trim().ToLower() -eq "n") {
                $DryRun = $false
                Write-Host "WARNING: Dry run disabled - changes will be ACTUALLY executed!" -ForegroundColor Red
                $confirm = Read-Host "Are you sure you want to continue? (yes/no)"
                if ($confirm.ToLower() -ne "yes") {
                    Write-Host "Cancelled by user." -ForegroundColor Yellow
                    exit 0
                }
            }
            else {
                Write-Host "Unknown choice, using DryRun = Yes" -ForegroundColor Yellow
                $DryRun = $true
            }

            # Site exclusions
            Write-Host "`n--- Site Exclusions ---" -ForegroundColor Cyan
            Write-Host "Current excluded sites:"
            if ($excludedSites.Count -eq 0) {
                Write-Host "  (none)" -ForegroundColor Gray
            } else {
                foreach ($site in $excludedSites) {
                    Write-Host "  - $site" -ForegroundColor Gray
                }
            }
            
            $modifyExclusions = Read-Host "`nModify excluded sites? (y/N) [N]"
            if ($modifyExclusions.Trim().ToLower() -eq "y") {
                Write-Host "`nOptions:" -ForegroundColor Yellow
                Write-Host "  1. Add sites to exclusion list"
                Write-Host "  2. Clear all exclusions (process ALL sites)"
                Write-Host "  3. Keep current list"
                $choice = Read-Host "Choose option (1-3) [3]"
                
                if ($choice -eq "1") {
                    Write-Host "`n--- Add Sites to Exclusion List ---" -ForegroundColor Yellow
                    Write-Host "Enter site URLs to exclude (one per line, empty line to finish):" -ForegroundColor Yellow
                    Write-Host "`nExpected URL format:" -ForegroundColor Green
                    Write-Host "  https://[TENANT].sharepoint.com/sites/[SITENAME]" -ForegroundColor Green
                    Write-Host "`nExamples for tenant '$TenantName':" -ForegroundColor Green
                    Write-Host "  - https://$TenantName.sharepoint.com/sites/DoNotTouch" -ForegroundColor Gray
                    Write-Host "  - https://$TenantName.sharepoint.com/sites/HR-Records" -ForegroundColor Gray
                    Write-Host "  - https://$TenantName.sharepoint.com" -ForegroundColor Gray
                    Write-Host ""
                    
                    $newExclusions = @()
                    do {
                        $siteUrl = Read-Host "Site URL"
                        if (-not [string]::IsNullOrWhiteSpace($siteUrl)) {
                            $siteUrl = $siteUrl.Trim()
                            if ($siteUrl -match "^https://.*\\.sharepoint\\.com(/.*)?$") {
                                $newExclusions += $siteUrl
                                Write-Host "  [OK] Added: $siteUrl" -ForegroundColor Green
                            } else {
                                Write-Host "  [ERROR] Invalid URL format. Must be: https://[TENANT].sharepoint.com[/sites/NAME]" -ForegroundColor Red
                            }
                        }
                    } while (-not [string]::IsNullOrWhiteSpace($siteUrl))
                    
                    if ($newExclusions.Count -gt 0) {
                        $excludedSites = $excludedSites + $newExclusions | Select-Object -Unique
                        Write-Host "`n$($newExclusions.Count) site(s) added to exclusion list" -ForegroundColor Green
                    }
                }
                elseif ($choice -eq "2") {
                    $confirmClear = Read-Host "Are you sure you want to clear ALL exclusions? (yes/no)"
                    if ($confirmClear.ToLower() -eq "yes") {
                        $excludedSites = @()
                        Write-Host "All exclusions cleared. ALL sites will be processed!" -ForegroundColor Yellow
                    } else {
                        Write-Host "Keeping current exclusion list" -ForegroundColor Gray
                    }
                }
            }
        }
        elseif ($Mode -eq "Analyze") {
            Write-Host "`n--- Analyze Configuration ---" -ForegroundColor Cyan
            Write-Host "The script will connect to SharePoint Online and retrieve version data." -ForegroundColor Yellow
            Write-Host "This will use your current Office 365 credentials." -ForegroundColor Gray
            
            $htmlInput = Read-Host "`nHTML output file path [$HtmlReportPath]"
            if (-not [string]::IsNullOrWhiteSpace($htmlInput)) {
                $HtmlReportPath = $htmlInput.Trim()
            }
        }
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  CONFIGURATION" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Mode           : $Mode"
    Write-Host "Tenant         : $TenantName"
    Write-Host "Admin URL      : $adminUrl"
    if ($Mode -eq "Cleanup") {
        Write-Host "Strategy       : $versionStrategy" -ForegroundColor Yellow
        if ($versionStrategy -eq "manual") {
            Write-Host "RetentionDays  : $RetentionDays"
        }
        Write-Host "DryRun         : $DryRun" -ForegroundColor $(if ($DryRun) { "Green" } else { "Red" })
        Write-Host "Excluded Sites : $($excludedSites.Count)" -ForegroundColor $(if ($excludedSites.Count -eq 0) { "Yellow" } else { "Cyan" })
    }
    elseif ($Mode -eq "Analyze") {
        Write-Host "RetentionDays  : $RetentionDays"
        Write-Host "HtmlReportPath : $HtmlReportPath"
    }
    Write-Host "========================================`n" -ForegroundColor Cyan

    $proceed = Read-Host "Continue with this configuration? (Y/n)"
    if ($proceed.ToLower() -eq "n") {
        Write-Host "Cancelled by user." -ForegroundColor Yellow
        exit 0
    }
    
    # Save config for next run
    $saveConfig = Read-Host "`nSave this configuration for next time? (y/N) [N]"
    if ($saveConfig.ToLower() -eq "y") {
        Save-Config $configFile
    }
}

###############################################################
# MODE: CLEANUP
###############################################################

function Run-Cleanup {
    Log "=== MODE: CLEANUP (DryRun = $DryRun, Tenant = $TenantName) ==="
    Log "Running pre-flight checks for Cleanup..."

    # Ensure retention is a valid integer > 0
    $RetentionDaysInt = 0
    $parsedRetention = 0
    if ([int]::TryParse([string]$RetentionDays, [ref]$parsedRetention) -and $parsedRetention -gt 0) {
        $RetentionDaysInt = $parsedRetention
    } else {
        $RetentionDaysInt = 180
        Log "[WARN] RetentionDays invalid or <= 0; defaulting to 180"
    }
    Log "Using retention (days): $RetentionDaysInt"

    if ($PSVersionTable.PSVersion.Major -ne 5) {
        Fail "This script must be run in Windows PowerShell 5.1."
    }
    Log "PowerShell version OK"

    if (-not (Get-Module -ListAvailable -Name Microsoft.Online.SharePoint.PowerShell)) {
        Fail "Microsoft.Online.SharePoint.PowerShell module missing. Install with: Install-Module Microsoft.Online.SharePoint.PowerShell -Force"
    }
    Log "SPO module found"

    Log "Connecting to SharePoint Online Admin..."
    Connect-SPOService -Url $adminUrl

    Log "Retrieving all site collections..."
    $sites = Get-SPOSite -Limit All
    Log ("Total sites found: " + $sites.Count)

    $processedCount = 0
    $skippedCount = 0
    $errorCount = 0

    foreach ($site in $sites) {
        if ($excludedSites -contains $site.Url) {
            Log ("[SKIPPED] $($site.Url)")
            $skippedCount++
            continue
        }

        Log ("[" + ($processedCount + 1) + "/" + $sites.Count + "] Processing: $($site.Url)")
        $siteHadError = $false

        if ($versionStrategy -eq "none") {
            Log "  [SKIP] No version strategy changes (strategy = none)"
            $processedCount++
            continue
        }

        if ($DryRun) {
            if ($versionStrategy -eq "auto") {
                Log "  DRY RUN: Would enable Microsoft auto-management (30 days default)"
            }
            else {
                Log "  DRY RUN: Would enable auto-trimming with $RetentionDays days retention"
                Log "  DRY RUN: Would start immediate cleanup job"
            }
        }
        else {
            try {
                if ($versionStrategy -eq "auto") {
                    Set-SPOSite -Identity $site.Url `
                        -EnableAutoExpirationVersionTrim $true `
                        -ApplyToExistingDocumentLibraries `
                        -Confirm:$false
                    Log "  [OK] Microsoft auto-management enabled (30 days default)"
                }
                else {
                    # First disable, then reconfigure with new retention days
                    Set-SPOSite -Identity $site.Url `
                        -EnableAutoExpirationVersionTrim $false `
                        -ApplyToExistingDocumentLibraries `
                        -Confirm:$false
                    Log "  [OK] Auto-expiration disabled (reconfiguring...)"
                    
                    # Now enable with new retention days
                    Set-SPOSite -Identity $site.Url `
                        -EnableAutoExpirationVersionTrim $true `
                        -ExpireVersionsAfterDays $RetentionDaysInt `
                        -ApplyToExistingDocumentLibraries `
                        -Confirm:$false
                    Log "  [OK] Auto-trimming reconfigured: $RetentionDaysInt days retention"
                    
                    # Start immediate cleanup job for manual strategy
                    try {
                        New-SPOSiteFileVersionBatchDeleteJob -Identity $site.Url -DeleteBeforeDays $RetentionDaysInt -Confirm:$false
                        Log "  [OK] Cleanup job started immediately"
                    }
                    catch {
                        Log ("  [WARN] Could not start cleanup job: " + $_.Exception.Message)
                    }
                }
            }
            catch {
                Log ("  [ERROR] Setting version strategy: " + $_.Exception.Message)
                $siteHadError = $true
                $errorCount++
            }
        }
        
        if (-not $siteHadError) {
            $processedCount++
        }
    }

    Log "`n========================================"
    Log "  CLEANUP SUMMARY"
    Log "========================================"
    Log ("Mode           : " + $(if ($DryRun) { "DRY RUN" } else { "LIVE" }))
    Log ("Total sites    : " + $sites.Count)
    Log ("Processed      : " + $processedCount)
    Log ("Skipped        : " + $skippedCount)
    Log ("Errors         : " + $errorCount)
    Log "========================================"
    Log ("=== CLEANUP COMPLETED ===")
}

###############################################################
# MODE: ANALYZE (DIRECT SHAREPOINT CONNECTION)
###############################################################

function Run-Analyze {
    Log "=== MODE: ANALYZE (Tenant = $TenantName) ==="
    Log ("Using HtmlReportPath = " + $HtmlReportPath)
    Log ("RetentionDays = " + $RetentionDays)

    Log "Running pre-flight checks for Analyze..."

    if ($PSVersionTable.PSVersion.Major -ne 5) {
        Fail "This script must be run in Windows PowerShell 5.1."
    }
    Log "PowerShell version OK"

    if (-not (Get-Module -ListAvailable -Name Microsoft.Online.SharePoint.PowerShell)) {
        Fail "Microsoft.Online.SharePoint.PowerShell module missing."
    }
    Log "SPO module found"

    Log "Connecting to SharePoint Online Admin..."
    Connect-SPOService -Url $adminUrl

    Log "Retrieving all site collections..."
    $sites = Get-SPOSite -Limit All
    Log ("Total sites found: " + $sites.Count)

    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $siteSummaries = @()

    foreach ($site in $sites) {
        $siteIndex = ($sites.IndexOf($site) + 1)
        
        if ($excludedSites -contains $site.Url) {
            Log ("[" + $siteIndex + "/" + $sites.Count + "] SKIPPED (excluded): $($site.Url)")
            continue
        }
        
        Log ("[" + $siteIndex + "/" + $sites.Count + "] Analyzing: $($site.Url)")

        try {
            $siteQuota = Get-SPOSite -Identity $site.Url -Detailed -ErrorAction SilentlyContinue
            
            if ($siteQuota) {
                $usedSpace = $siteQuota.StorageUsageCurrent
                $siteGB = [math]::Round($usedSpace / 1024, 2)
                
                Log ("  Site storage: $siteGB GB")

                $summary = [PSCustomObject]@{
                    SiteUrl              = $site.Url
                    SiteTitle            = $site.Title
                    TotalVersions        = "N/A"
                    VersionsOlderThanX   = "N/A"
                    TotalSizeGB          = $siteGB
                    OlderSizeGB          = "N/A"
                }
                $siteSummaries += $summary
            }
        }
        catch {
            Log ("  [WARN] Could not analyze: " + $_)
        }
    }

    Log ("Analysis complete. Found " + $siteSummaries.Count + " sites with version data.")

    if ($siteSummaries.Count -gt 0) {
        Log "Generating HTML report..."
        
        $htmlDir = Split-Path $HtmlReportPath
        if ($htmlDir -and !(Test-Path $htmlDir)) {
            New-Item -ItemType Directory -Path $htmlDir -Force | Out-Null
        }

        $htmlContent = '<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>SharePoint Version Analysis - ' + $TenantName + '</title>
<style>
body { font-family: Arial, sans-serif; background: #f5f7fb; margin: 0; padding: 20px; color: #222; }
.container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 8px; padding: 30px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
h1 { margin-top: 0; color: #1f3b57; }
.meta { font-size: 13px; color: #666; margin-bottom: 20px; }
table { width: 100%; border-collapse: collapse; margin-top: 15px; }
thead { background: linear-gradient(90deg, #304ffe, #00b0ff); color: white; }
th, td { padding: 10px; text-align: left; border-bottom: 1px solid #e2e5ee; }
tr:nth-child(even) { background-color: #f9fafc; }
tr:hover { background-color: #eef3ff; }
th { font-weight: 600; }
.number { text-align: right; }
.pill-high { background: #ffebee; color: #c62828; padding: 2px 8px; border-radius: 3px; display: inline-block; }
.footer { margin-top: 20px; font-size: 12px; color: #888; }
</style>
</head>
<body>
<div class="container">
<h1>SharePoint Version Analysis</h1>
<div class="meta">
    Tenant: <strong>' + $TenantName + '</strong><br/>
    Generated: ' + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + '<br/>
    Cutoff: Versions older than ' + $RetentionDays + ' days<br/>
    Total sites analyzed: <strong>' + $siteSummaries.Count + '</strong>
</div>
<table>
<thead>
<tr>
    <th>Site URL</th>
    <th>Site Title</th>
    <th class="number">Total Versions</th>
    <th class="number">Versions &gt; ' + $RetentionDays + ' days</th>
    <th class="number">Total Size (GB)</th>
    <th class="number">Older Size (GB)</th>
</tr>
</thead>
<tbody>'

        foreach ($s in $siteSummaries) {
            $olderClass = if ($s.OlderSizeGB -ge 1) { "pill-high" } else { "" }
            $olderDisplay = if ($s.OlderSizeGB -gt 0) { "<span class='" + $olderClass + "'>" + $s.OlderSizeGB + " GB</span>" } else { $s.OlderSizeGB }
            
            $htmlContent += '
<tr>
    <td>' + $s.SiteUrl + '</td>
    <td>' + $s.SiteTitle + '</td>
    <td class="number">' + $s.TotalVersions + '</td>
    <td class="number">' + $s.VersionsOlderThanX + '</td>
    <td class="number">' + $s.TotalSizeGB + '</td>
    <td class="number">' + $olderDisplay + '</td>
</tr>'
        }

        $htmlContent += '
</tbody>
</table>
<div class="footer">
    Report generated at ' + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + '
</div>
</div>
</body>
</html>'

        try {
            Set-Content -Path $HtmlReportPath -Value $htmlContent -Encoding UTF8 -ErrorAction Stop
            Log ("HTML report written: " + $HtmlReportPath)
        }
        catch {
            Fail "Failed to write HTML report: $_"
        }
    }

    Log "=== ANALYZE COMPLETED ==="
}

###############################################################
# MAIN
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
