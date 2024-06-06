  
    #################################################################################################################
    #                                                                                                               #
    #           This script adds the specified account as owner to all the sharepoint sites                         #
    #                                                                                                               #
    #                                                                                                               #
    #################################################################################################################


#Config parameters for SharePoint Online Admin Center (-admin.sharepoint.com/) and Timezone description
 
 
 #Parameters
 $TenantAdminURL = "https://xxxxxxxxxx-admin.sharepoint.com"
 $SiteCollAdmin="UserToAdd@domain.com"
    
 #Connect to Admin Center
 Connect-PnPOnline -Url $TenantAdminURL -Interactive
  
 #Get All Site collections and Iterate through
 $SiteCollections = Get-PnPTenantSite
 ForEach($Site in $SiteCollections)
 { 
     #Add Site collection Admin
     Set-PnPTenantSite -Url $Site.Url -Owners $SiteCollAdmin
     Write-host "Added $($SiteCollAdmin) to $($Site.URL) as owner"
 } 
 