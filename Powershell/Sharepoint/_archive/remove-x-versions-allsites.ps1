#Uses the SPO-versionbatchdelete to delete older versions of files

# Variables
$installerUrl = "https://www.microsoft.com/en-us/download/details.aspx?id=35588"
$installerPath = "$env:TEMP\SharePointOnlineManagementShell.msi"
$adminUrl = "https://XXXX-admin.sharepoint.com/"
$majorVersionLimit = 2
$majorWithMinorVersionsLimit = 0

# Function to check if the software needs to be installed
function Install-SharePointManagementShell {
    $response = Read-Host "Do you want to install the SharePoint Online Management Shell? (Y/N)"
    if ($response -eq 'Y' -or $response -eq 'y') {
        Write-Host "Downloading and installing SharePoint Online Management Shell..."
        
        # Download the installer
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

        # Install the software (this will require elevated privileges)
        Start-Process msiexec.exe -ArgumentList "/i", $installerPath, "/quiet", "/norestart" -Wait
        Write-Host "Installation complete."
    }
    else {
        Write-Host "Skipping SharePoint Online Management Shell installation."
    }
}

# Step 1: Ask if the software needs to be installed
Install-SharePointManagementShell

# Step 2: Connect to SharePoint Online Admin Service
Write-Host "Connecting to SharePoint Online Admin site: $adminUrl"
Connect-SPOService -Url $adminUrl

# Step 3: Delete old versions for all existing SharePoint sites
$sites = Get-SPOSite

foreach ($site in $sites) {
    $siteUrl = $site.Url
    Write-Host "Processing site: $siteUrl"
    
    # Run the New-SPOSiteFileVersionBatchDeleteJob cmdlet for each site
    New-SPOSiteFileVersionBatchDeleteJob -Identity $siteUrl -MajorVersionLimit $majorVersionLimit -MajorWithMinorVersionsLimit $majorWithMinorVersionsLimit
    Write-Host "Batch delete job initiated for site: $siteUrl"
}

Write-Host "Script completed successfully."