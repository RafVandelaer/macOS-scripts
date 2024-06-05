 
    #################################################################################################################
    #                                                                                                               #
    #        This script changes the timezone of all the existing sites in your Sharepoint.                         #
    #        Make sure the used credentials are admin over these sites. If this is not the case, you could use      #
    #        add-admin-to-all-sharepoint-sites.ps1 in my github.                                                    #
    #        You need to install the pnp.powershell module with Install-Module PnP.PowerShell                       #
    #                                                                                                               #
    #        All the TimeZone IDs can be found at                                                                   #
    #        https://pkbullock.com/resources/reference-sharepoint-time-zone-ids                                     #
    #                                                                                                               #
    #        Make sure to change the variables according to your preferences                                        #
    #                                                                                                               #
    #                                                                                                               #
    #################################################################################################################


#Config parameters for SharePoint Online Admin Center (-admin.sharepoint.com/) and Timezone description
 $AdminSiteURL = "https://xxxxxxxxxxxxxxxxxxxxxxx-admin.sharepoint.com/"
 $timeZoneId = 3
 
 #Load security protocol
 [System.Net.ServicePointManager]::SecurityProtocol = "Tls12"

  
 #Get credentials to connect to SharePoint Online Admin Center
 $AdminCredentials = Get-Credential
  
 #Connect to SharePoint Online Tenant Admin
 Connect-pnpOnline -URL $AdminSiteURL -Credential $AdminCredentials
 
  
 #Get all Site Collections
 $SitesCollection = Get-PnPTenantSite
 
 #Iterate through each site collection
 ForEach($Site in $SitesCollection)
 {
     Write-host -f Yellow "Setting Timezone for Site Collection: "$Site.URL
  
      Connect-pnponline -Url $Site.URL -Credentials $AdminCredentials
     $web = Get-PnPWeb -Includes RegionalSettings,RegionalSettings.TimeZones
     $timeZone = $web.RegionalSettings.TimeZones | Where-Object {$_.Id -eq $timeZoneId}
     $web.RegionalSettings.TimeZone = $timeZone
     $web.Update()
     Invoke-PnPQuery
 
  
 } 