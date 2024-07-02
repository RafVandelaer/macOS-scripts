
     #################################################################################################################
    #                                                                                                               #
    #           This script removes versioning to a specified number so you restore some space in Sharepoint        #
    #                                You need to run this script in Powershell 7                                    #
    #                                                                                                               #
    #################################################################################################################


    
 #Config Parameters
 $SiteURL = "https://SITENAME.sharepoint.com/sites/SITENAME/"

 $VersionsToKeep = 7
  
 Try {
     #Connect to PnP Online
     Connect-PnPOnline -Url $SiteURL -Interactive
  
     #Get the Context
     $Ctx= Get-PnPContext
  
     #Exclude certain libraries
     $ExcludedLists = @("Form Templates", "Preservation Hold Library","Site Assets", "Pages", "Site Pages", "Images",
                             "Site Collection Documents", "Site Collection Images","Style Library")
  
     #Get All document libraries
     $DocumentLibraries = Get-PnPList | Where-Object {$_.BaseType -eq "DocumentLibrary" -and $_.Title -notin $ExcludedLists -and $_.Hidden -eq $false}
 
  
     #Iterate through each document library
     ForEach($Library in $DocumentLibraries)
     {
         Write-host "Processing Document Library:"$Library.Title -f Magenta
  
         #Get All Items from the List - Exclude 'Folder' List Items
         $ListItems = Get-PnPListItem -List $Library -PageSize 5000 | Where {$_.FileSystemObjectType -eq "File"}
          #$ListItems = Get-PnPListItem -List $Library -PageSize 5000 | Where { $_[“File_x0020_Type”] -in (“vwx”)}
         #$DocumentItems = $ListItems | Where { $_[“File_x0020_Type”] -in (“vwx”)}
  
         #Loop through each file
         #Hier ook
         ForEach ($Item in $ListItems)
         #ForEach ($Item in $DocumentItems)
         {
             try{
 
             Start-Sleep -Seconds 0.5
 
                 #Get File Versions
                 $File = $Item.File
                 $Versions = $File.Versions
                 $Ctx.Load($File)
                 $Ctx.Load($Versions)
                 $Ctx.ExecuteQuery()
   
                 Write-host -f Yellow "`tScanning File:"$File.Name
                 $VersionsCount = $Versions.Count
                 $VersionsToDelete = $VersionsCount - $VersionsToKeep
                 If($VersionsToDelete -gt 0)
                 {
                     write-host -f Cyan "`t Total Number of Versions of the File:" $VersionsCount
                     $VersionCounter= 0
                     #Delete versions
                     For($i=0; $i -lt $VersionsToDelete; $i++)
                     {
                         If($Versions[$VersionCounter].IsCurrentVersion)
                         {
                         
                            $VersionCounter++
                            Write-host -f Magenta "`t`t Retaining Current Major Version:"$Versions[$VersionCounter].VersionLabel
                            Continue
                         }
                         Write-host -f Cyan "`t Deleting Version:" $Versions[$VersionCounter].VersionLabel
                         $Versions[$VersionCounter].DeleteObject()
                     }
                     $Ctx.ExecuteQuery()
                     Write-Host -f Green "`t Version History is cleaned for the File:"$File.Name
                 }
             } catch {
                 write-host -f Red $Error[0].Exception
             }
         }
     }
 }
 Catch {
     write-host -f Red "Error Cleaning up Version History!" $_.Exception.Message
     write-host -f Red $Error[0].Exception
 }
 
 
 