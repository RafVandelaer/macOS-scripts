 # Connect to Exchange Online
 Import-Module ExchangeOnlineManagement
 Connect-ExchangeOnline 
 
 # Get all mailboxes
 $AllMailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited
 
 # Loop through each mailbox
 foreach ($Mailbox in $AllMailboxes) {
     # Skip shared/system mailboxes
     if ($Mailbox.RecipientTypeDetails -eq "SharedMailbox") {
         Write-Host "Skipping shared mailbox:" $Mailbox.PrimarySmtpAddress -ForegroundColor Yellow
         continue
     }
 
     # Get all other users
     $OtherUsers = $AllMailboxes | Where-Object { $_.PrimarySmtpAddress -ne $Mailbox.PrimarySmtpAddress }
 
     foreach ($OtherUser in $OtherUsers) {
         $AgendaPath = "$($Mailbox.PrimarySmtpAddress):\Agenda"
         $CalendarPath = "$($Mailbox.PrimarySmtpAddress):\Calendar"
         
         try {
             # Try setting permissions on "Agenda"
             Add-MailboxFolderPermission -Identity $AgendaPath -User $OtherUser.PrimarySmtpAddress -AccessRights Editor
             Write-Host "Granted Editor permissions to $($OtherUser.PrimarySmtpAddress) on $($Mailbox.PrimarySmtpAddress)'s Agenda" -ForegroundColor Green
         } catch {
             # If "Agenda" fails, try "Calendar"
             Write-Host "Failed to set permissions on Agenda for $($OtherUser.PrimarySmtpAddress). Trying Calendar..." -ForegroundColor Yellow
             try {
                 Add-MailboxFolderPermission -Identity $CalendarPath -User $OtherUser.PrimarySmtpAddress -AccessRights Editor
                 Write-Host "Granted Editor permissions to $($OtherUser.PrimarySmtpAddress) on $($Mailbox.PrimarySmtpAddress)'s Calendar" -ForegroundColor Green
             } catch {
                 # Log the failure if both attempts fail
                 Write-Host "Failed to set permissions for $($OtherUser.PrimarySmtpAddress) on both Agenda and Calendar for $($Mailbox.PrimarySmtpAddress): $_" -ForegroundColor Red
             }
         }
     }
 }
 
 # Disconnect from Exchange Online
 Disconnect-ExchangeOnline -Confirm:$false
  
 