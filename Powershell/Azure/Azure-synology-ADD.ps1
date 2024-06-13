  
    ####################################################################################################################
    #                                                                                                                  #
    #           This script creates an Azure AD domain service used for connecting a Synology to Entra.                #
    #           Use this script when your domain name extends the 15 characters. Otherwise use the GUI:                #
    #           https://kb.synology.com/nl-nl/DSM/tutorial/How_to_join_NAS_to_Azure_AD_Domain                          #
    #           Powershell isn't limited to 15 characters when creating the instance                                   #
    #                                                                                                                  #
    #           First make sure to do the following:                                                                   #
    #           1.  Install Azure Powershell Module:                                                                   #
    #               learn.microsoft.com/en-us/powershell/azure/install-azure-powershell                                #
    #           2.  Install MS Graph Module:                                                                           #
    #               learn.microsoft.com/en-us/powershell/microsoftgraph/installation?view=graph-powershell-1.0         #    
    #           3.  Install-Module -Name Az.ADDomainServices                                                           #
    #           4.  Run Connect-MgGraph -Scopes AppRoleAssignment.ReadWrite.All,Application.ReadWrite.All -NoWelcome   #
    #           5.  Change the variables below before running the script                                               #
    #                                                                                                                  #
    #                                                                                                                  #
    ####################################################################################################################


# Change the following values to match your deployment.
            
            #Global Admin account
            $AaddsAdminUserUpn = "admin@domain.com"
            #Go to the subscription in entra portal and paste the ID
            $AzureSubscriptionId = "00000000-0000-0000-0000-000000000000"
            #verified domain name of the tenant
            $ManagedDomainName = "domain.com"
            #Any name you want to use
            $ResourceGroupName = "Synology"
            $VnetName = "DomainServicesVNet_WEU"
            #Region
            $AzureLocation = "westeurope"

# Connect to your Azure AD directory.
Connect-AzureAD

# Login to your Azure subscription.
Connect-AzAccount

# Create the service principal for Azure AD Domain Services.
New-AzureADServicePrincipal -AppId "2565bd9d-da50-47d4-8b85-4c97f669dc36"

# Create the delegated administration group for AAD Domain Services.
New-AzureADGroup -DisplayName "AAD DC Administrators" `
  -Description "Delegated group to administer Azure AD Domain Services" `
  -SecurityEnabled $true -MailEnabled $false `
  -MailNickName "AADDCAdministrators"

# First, retrieve the object ID of the newly created 'AAD DC Administrators' group.
$GroupObjectId = Get-AzureADGroup `
  -Filter "DisplayName eq 'AAD DC Administrators'" | `
  Select-Object ObjectId

# Now, retrieve the object ID of the user you'd like to add to the group.
$UserObjectId = Get-AzureADUser `
  -Filter "UserPrincipalName eq '$AaddsAdminUserUpn'" | `
  Select-Object ObjectId

# Add the user to the 'AAD DC Administrators' group.
Add-AzureADGroupMember -ObjectId $GroupObjectId.ObjectId -RefObjectId $UserObjectId.ObjectId

# Register the resource provider for Azure AD Domain Services with Resource Manager.
Register-AzResourceProvider -ProviderNamespace Microsoft.AAD

# Create the resource group.
New-AzResourceGroup `
  -Name $ResourceGroupName `
  -Location $AzureLocation

# Create the dedicated subnet for AAD Domain Services.
$AaddsSubnet = New-AzVirtualNetworkSubnetConfig `
  -Name DomainServices `
  -AddressPrefix 10.0.0.0/24

$WorkloadSubnet = New-AzVirtualNetworkSubnetConfig `
  -Name Workloads `
  -AddressPrefix 10.0.1.0/24

# Create the virtual network in which you will enable Azure AD Domain Services.
$Vnet=New-AzVirtualNetwork `
  -ResourceGroupName $ResourceGroupName `
  -Location $AzureLocation `
  -Name $VnetName `
  -AddressPrefix 10.0.0.0/16 `
  -Subnet $AaddsSubnet,$WorkloadSubnet

# Enable Azure AD Domain Services for the directory.
New-AzResource -ResourceId "/subscriptions/$AzureSubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.AAD/DomainServices/$ManagedDomainName" `
  -Location $AzureLocation `
  -Properties @{"DomainName"=$ManagedDomainName; `
    "SubnetId"="/subscriptions/$AzureSubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/virtualNetworks/$VnetName/subnets/DomainServices"} `
  -ApiVersion 2017-06-01 -Force -Verbose