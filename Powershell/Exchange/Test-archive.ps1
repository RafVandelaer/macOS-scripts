param(
    [string]$UserPrincipalName
)

Write-Host "=== ARCHIVE TROUBLESHOOTING ===" -ForegroundColor Cyan

# ================================================================
# 0. VRAAG EMAILADRES (UPN) ALS HET NIET IS MEEGEGEVEN
# ================================================================

if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {
    $UserPrincipalName = Read-Host "Geen UserPrincipalName opgegeven. Vul het e-mailadres in"
}

if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {
    Write-Host "Geen geldig e-mailadres opgegeven. Script beëindigd." -ForegroundColor Red
    exit
}


# ================================================================
# 1. CONTROLEREN OF EXCHANGE ONLINE MODULE AANWEZIG IS
# ================================================================

Write-Host "[1] Exchange Online module controleren..." -ForegroundColor Yellow

$exoModule = Get-Module -ListAvailable -Name ExchangeOnlineManagement

if (-not $exoModule) {
    Write-Host "ExchangeOnlineManagement module niet gevonden." -ForegroundColor Red
    $install = Read-Host "Module installeren? (Y/N)"

    if ($install -eq "Y") {
        try {
            Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "Module geïnstalleerd." -ForegroundColor Green
        } catch {
            Write-Host "Installatie mislukt. Script beëindigd." -ForegroundColor Red
            exit
        }
    } else {
        Write-Host "Module vereist. Script beëindigd." -ForegroundColor Red
        exit
    }
}

if (-not (Get-Module ExchangeOnlineManagement)) {
    try {
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        Write-Host "Module geïmporteerd." -ForegroundColor Green
    } catch {
        Write-Host "Kon ExchangeOnlineManagement niet importeren." -ForegroundColor Red
        exit
    }
}

if (-not (Get-Command Connect-ExchangeOnline -ErrorAction SilentlyContinue)) {
    Write-Host "Connect-ExchangeOnline ontbreekt. Module-installatie lijkt corrupt." -ForegroundColor Red
    exit
}


# ================================================================
# 2. VERBINDEN MET EXCHANGE ONLINE
# ================================================================

Write-Host "[2] Verbinden met Exchange Online..." -ForegroundColor Yellow
try {
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
} catch {}

Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop


# ================================================================
# 3. MAILBOX OPHALEN
# ================================================================

Write-Host "`n[3] Mailbox ophalen..." -ForegroundColor Yellow
try {
    $mbx = Get-Mailbox -Identity $UserPrincipalName -ErrorAction Stop
    Write-Host "Mailbox gevonden." -ForegroundColor Green
} catch {
    Write-Host "Mailbox niet gevonden." -ForegroundColor Red
    exit
}


# ================================================================
# 4. ARCHIVE STATUS
# ================================================================

Write-Host "`n[4] Archive status..." -ForegroundColor Yellow
$archiveEnabled = ($mbx.ArchiveStatus -eq "Active")

if ($archiveEnabled) {
    Write-Host "Archief is geactiveerd." -ForegroundColor Green
} else {
    Write-Host "Archief is niet geactiveerd." -ForegroundColor Red

    $activate = Read-Host "Archief activeren? (Y/N)"
    if ($activate -eq "Y") {
        Enable-Mailbox -Identity $UserPrincipalName -Archive
        Write-Host "Archief geactiveerd. Provisioning duurt enkele minuten." -ForegroundColor Green
    }
}


# ================================================================
# 5. AUTO-EXPANDING ARCHIVE
# ================================================================

Write-Host "`n[5] Auto-Expanding Archive..." -ForegroundColor Yellow

$autoExpand = $null
try {
    $autoExpand = (Get-Mailbox -Identity $UserPrincipalName).AutoExpandingArchiveEnabled
} catch {
    $autoExpand = $null
}

if ($autoExpand -eq $true) {
    Write-Host "Auto-expanding archive is ingeschakeld." -ForegroundColor Green
} elseif ($autoExpand -eq $false) {
    Write-Host "Auto-expanding archive is uitgeschakeld." -ForegroundColor DarkYellow
    $fixAuto = Read-Host "Auto-Expanding Archive inschakelen? (Y/N)"
    if ($fixAuto -eq "Y") {
        Enable-Mailbox -Identity $UserPrincipalName -AutoExpandingArchive
        Write-Host "Auto-expanding archive ingeschakeld." -ForegroundColor Green
    }
} else {
    Write-Host "Auto-expanding archive status niet beschikbaar." -ForegroundColor DarkYellow
}


# ================================================================
# 6. RETENTION POLICY + AUTOMATISCHE CREATIE
# ================================================================

Write-Host "`n[6] Retention Policy..." -ForegroundColor Yellow

$policyName = $mbx.RetentionPolicy
$policy = $null

try {
    $policy = Get-RetentionPolicy -Identity $policyName -ErrorAction Stop
    Write-Host "Retention Policy '$policyName' gevonden." -ForegroundColor Green
} catch {
    Write-Host "Retention Policy '$policyName' ontbreekt of ongeldig." -ForegroundColor Red
}

if (-not $policy) {
    $create = Read-Host "Nieuwe Retention Policy aanmaken? (Y/N)"
    if ($create -eq "Y") {

        $daysInput = Read-Host "Aantal dagen retention? (voorstel: 1095)"
        $days = if ([string]::IsNullOrWhiteSpace($daysInput)) { 1095 } else { [int]$daysInput }

        $tagName = "Archive After $days Days"
        $newPolicyName = "MRM Policy - $days Days Archive"

        # Retention Tag aanmaken indien nodig
        try {
            $existingTag = Get-RetentionPolicyTag -Identity $tagName -ErrorAction Stop
        } catch {
            New-RetentionPolicyTag -Name $tagName -Type All -RetentionEnabled $true -AgeLimitForRetention $days -RetentionAction MoveToArchive | Out-Null
        }

        # Retention Policy aanmaken indien nodig
        try {
            $existingPolicy = Get-RetentionPolicy -Identity $newPolicyName -ErrorAction Stop
        } catch {
            New-RetentionPolicy -Name $newPolicyName -RetentionPolicyTagLinks $tagName | Out-Null
        }

        # Toewijzen aan mailbox
        $assign = Read-Host "Nieuwe policy toewijzen aan $UserPrincipalName ? (Y/N)"
        if ($assign -eq "Y") {
            Set-Mailbox -Identity $UserPrincipalName -RetentionPolicy $newPolicyName
            Write-Host "Policy toegewezen." -ForegroundColor Green
            # Policy variabele updaten voor samenvatting
            try {
                $policy = Get-RetentionPolicy -Identity $newPolicyName -ErrorAction Stop
            } catch {
                $policy = $null
            }
        }
    }
}


# ================================================================
# 7. MRM STATUS
# ================================================================

Write-Host "`n[7] MRM status..." -ForegroundColor Yellow

$lastMRM = $null
try {
    $mrm = Get-MailboxStatistics $UserPrincipalName | Select LastProcessedTime
    $lastMRM = $mrm.LastProcessedTime
} catch {
    $lastMRM = $null
}

if ($lastMRM) {
    Write-Host "Laatste MRM verwerking: $lastMRM" -ForegroundColor Green
} else {
    Write-Host "MRM heeft nog niet gedraaid." -ForegroundColor Red
    $runMRM = Read-Host "MRM nu uitvoeren? (Y/N)"
    if ($runMRM -eq "Y") {
        Start-ManagedFolderAssistant -Identity $UserPrincipalName
        Write-Host "MRM gestart." -ForegroundColor Green
    }
}


# ================================================================
# 8. ARCHIVE STATISTICS
# ================================================================

Write-Host "`n[8] Archive usage..." -ForegroundColor Yellow
try {
    $stats = Get-MailboxStatistics -Identity $UserPrincipalName -Archive
    $stats | Select DisplayName,TotalItemSize,ItemCount | Format-List
} catch {
    Write-Host "Archive statistics niet beschikbaar." -ForegroundColor Red
}


# ================================================================
# 9. OUDSTE MAIL IN INBOX – ROBUUST (TAAL-EN LOCATIE-ONAFHANKELIJK)
# ================================================================

Write-Host "`n[9] Oudste mail in Inbox..." -ForegroundColor Yellow
$inboxOldest = $null
$inbox = $null

try {
    # 1. Probeer via FolderType (meest betrouwbaar)
    $inbox = Get-MailboxFolderStatistics -Identity $UserPrincipalName |
        Where-Object { $_.FolderType -eq "Inbox" }

    # 2. Indien niets gevonden → zoek op folderpath/naam
    if (-not $inbox -or $inbox.Count -eq 0) {
        $inbox = Get-MailboxFolderStatistics -Identity $UserPrincipalName |
            Where-Object {
                $_.FolderPath -match "Inbox" -or
                $_.Name -match "Inbox" -or
                $_.FolderPath -match "Postvak IN" -or
                $_.Name -match "Postvak IN" -or
                $_.FolderPath -match "Boîte de réception" -or
                $_.Name -match "Boîte de réception"
            }
    }

    # 3. Als we nu iets terugkrijgen, maar er zijn 0 items
    if ($inbox -and $inbox.ItemsInFolder -gt 0) {
        $inboxOldest = $inbox.OldestItemReceivedDate
        Write-Host "Oudste mail in Inbox: $inboxOldest" -ForegroundColor Green

    } elseif ($inbox -and $inbox.ItemsInFolder -eq 0) {
        Write-Host "Inbox is leeg." -ForegroundColor DarkYellow

    } else {
        Write-Host "Inbox niet gevonden via FolderType of naam. Fallback uitvoeren." -ForegroundColor DarkYellow
        
        # 4. Fallback: oudste mail in hele mailbox
        $allFolders = Get-MailboxFolderStatistics -Identity $UserPrincipalName |
            Where-Object { $_.ItemsInFolder -gt 0 }

        if ($allFolders) {
            $inboxOldest = ($allFolders | 
                Sort-Object OldestItemReceivedDate | 
                Select-Object -First 1).OldestItemReceivedDate

            Write-Host "Oudste mail in mailbox (fallback): $inboxOldest" -ForegroundColor Green
        } else {
            Write-Host "Geen items gevonden in mailbox of statistieken zijn niet beschikbaar." -ForegroundColor Red
        }
    }

} catch {
    Write-Host "Kon Inbox-informatie niet ophalen." -ForegroundColor Red
}


# ================================================================
# 10. DUIDELIJKE SAMENVATTING
# ================================================================

Write-Host "`n=== SAMENVATTING ===" -ForegroundColor Magenta

$s1 = if ($archiveEnabled) { "Archief: In orde (geactiveerd)" } else { "Archief: Niet in orde (uitgeschakeld)" }

if ($autoExpand -eq $true) {
    $s2 = "Auto-Expanding Archive: In orde (ingeschakeld)"
} elseif ($autoExpand -eq $false) {
    $s2 = "Auto-Expanding Archive: Uitgeschakeld"
} else {
    $s2 = "Auto-Expanding Archive: Status niet beschikbaar"
}

$s3 = if ($policy) { "Retention Policy: In orde ($($policy.Name))" } else { "Retention Policy: Ontbrak of niet geldig (eventueel nieuw aangemaakt)" }
$s4 = if ($lastMRM) { "MRM verwerking: In orde (laatste run: $lastMRM)" } else { "MRM verwerking: Niet in orde (nog niet uitgevoerd)" }
$s5 = if ($inboxOldest) { "Oudste mail in Inbox: $inboxOldest" } else { "Oudste mail in Inbox: Niet beschikbaar" }

$summary = @($s1, $s2, $s3, $s4, $s5) -join "`n"

Write-Host $summary -ForegroundColor White
Write-Host "`n=== EINDE ===" -ForegroundColor Magenta
