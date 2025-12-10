# SharePoint Online Version Management Tools

Two PowerShell scripts for managing SharePoint Online file versions.

## Scripts

### 1. `SPO-VersionCleanupAndAnalysis.ps1` (Legacy - with CSV support)
**Purpose:** Cleanup mode - Enable automatic version trimming and start cleanup jobs on all SharePoint sites

**Features:**
- Interactive or non-interactive mode
- Enable automatic version expiration trimming
- Start version cleanup jobs
- Optional site exclusions
- DryRun mode by default

**Usage:**
```powershell
.\SPO-VersionCleanupAndAnalysis.ps1
```

---

### 2. `SPO-VersionAnalyzer.ps1` (NEW - Recommended)
**Purpose:** Analyze - Connect directly to SharePoint and generate version statistics HTML report

**Features:**
- ✅ Direct SharePoint Online connection (no CSV needed!)
- ✅ Interactive setup with guided configuration
- ✅ Analyzes all sites and document libraries
- ✅ Calculates version statistics:
  - Total versions per site
  - Versions older than retention days
  - Total size and older size
- ✅ Generates beautiful HTML report
- ✅ Platform-aware (Windows, macOS, Linux)
- ✅ Automatic PnP.PowerShell module installation

**Usage:**
```powershell
.\SPO-VersionAnalyzer.ps1
```

**Example Output:**
```
========================================
  SHAREPOINT VERSION ANALYZER
========================================

Press Enter to accept the default value [in brackets].

HINT: Find tenant name in SharePoint Admin URL:
      https://[TENANT-NAME]-admin.sharepoint.com
      Example: https://contoso-admin.sharepoint.com -> enter: contoso

Tenant name (see hint above) [yourtenant]: Bridgeneers
Retention days (older than X days) [90]: 90
HTML output file [/tmp/spo-version-analysis.html]: 

========================================
  CONFIGURATION
========================================
Tenant         : Bridgeneers
Admin URL      : https://Bridgeneers-admin.sharepoint.com
RetentionDays  : 90
HtmlReportPath : /tmp/spo-version-analysis.html
========================================

Continue with this configuration? (Y/n): y

[Script connects and analyzes all sites...]
```

## Requirements

### PowerShell Version
- Windows PowerShell 5.1 (or PowerShell 7+ on macOS/Linux)

### Required Modules
- `Microsoft.Online.SharePoint.PowerShell`
- `PnP.PowerShell` (for SPO-VersionAnalyzer.ps1)

### Installation

**On Windows:**
```powershell
Install-Module Microsoft.Online.SharePoint.PowerShell -Force
Install-Module PnP.PowerShell -Force
```

**On macOS/Linux:**
```powershell
# First install PowerShell if not already installed
brew install powershell

# Then install modules
pwsh -Command {
    Install-Module Microsoft.Online.SharePoint.PowerShell -Force
    Install-Module PnP.PowerShell -Force
}
```

## Authentication

Both scripts will prompt you to authenticate with your Office 365 credentials when connecting to SharePoint Online. You'll need:
- SharePoint Admin credentials
- Access to the SharePoint Admin Center

## Output

### HTML Report Location
Default: `/tmp/spo-version-analysis.html` (macOS/Linux) or `C:\temp\spo-version-analysis.html` (Windows)

The HTML report includes:
- Tenant name and generation timestamp
- Table with all sites analyzed
- Version statistics per site
- Color-coded older size indicator

## Recommendations

1. **For Analysis:** Use `SPO-VersionAnalyzer.ps1` (newer, no CSV needed)
2. **For Cleanup:** Use `SPO-VersionCleanupAndAnalysis.ps1` in Cleanup mode with DryRun=Yes first
3. **Always start with DryRun enabled** before actual cleanup operations

## Troubleshooting

**"Module not found"**
```powershell
Install-Module PnP.PowerShell -Force -Scope CurrentUser
```

**"Cannot find drive C"** (on macOS)
- Scripts are platform-aware and use `/tmp` on macOS automatically

**"Access denied"**
- Ensure you have SharePoint Admin rights
- Check your Office 365 credentials

## Log Files

Logs are written to:
- `/tmp/spo-version-analyzer.log` (macOS/Linux)
- `C:\temp\spo-version-analyzer.log` (Windows)
