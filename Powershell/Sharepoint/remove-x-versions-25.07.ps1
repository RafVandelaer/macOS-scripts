# ================= CONFIGUREER DEZE PARAMETERS =================
$SiteURL  = "https://mvharchitecten.sharepoint.com/sites/MVHarchitects2"
$ClientId = "97ea0fe2-d16d-4ed1-b455-a5ea754e4581"
$VersionsToKeep = 2

# ================= CONNECTIE MAKEN MET SHAREPOINT =================
Try {
    Connect-PnPOnline -Url $SiteURL -Interactive -ClientId $ClientId
}
Catch {
    Write-Host -ForegroundColor Red "❌ Verbinding met SharePoint mislukt: $($_.Exception.Message)"
    Exit
}

# ================= VERSIEGESCHIEDENIS OPSCHONEN =================
Try {
    $Ctx = Get-PnPContext

    $ExcludedLists = @(
        "Form Templates", "Preservation Hold Library", "Site Assets", "Pages", "Site Pages", "Images",
        "Site Collection Documents", "Site Collection Images", "Style Library"
    )

    $DocumentLibraries = Get-PnPList | Where-Object {
        $_.BaseType -eq "DocumentLibrary" -and
        $_.Title -notin $ExcludedLists -and
        $_.Hidden -eq $false
    }

    ForEach ($Library in $DocumentLibraries) {
        Write-Host "📁 Verwerken van documentbibliotheek: $($Library.Title)" -ForegroundColor Magenta

        $ListItems = Get-PnPListItem -List $Library -PageSize 2000 | Where-Object {
            $_.FileSystemObjectType -eq "File"
        }

        ForEach ($Item in $ListItems) {
            Try {
                $File = $Item.File
                $Versions = $File.Versions
                $Ctx.Load($File)
                $Ctx.Load($Versions)
                $Ctx.ExecuteQuery()

                Write-Host -ForegroundColor Yellow "`tBestand gescand: $($File.Name)"
                $VersionsCount = $Versions.Count
                $VersionsToDelete = $VersionsCount - $VersionsToKeep

                If ($VersionsToDelete -gt 0) {
                    Write-Host -ForegroundColor Cyan "`t Aantal versies: $VersionsCount"
                    $VersionCounter = 0

                    For ($i = 0; $i -lt $VersionsToDelete; $i++) {
                        If ($Versions[$VersionCounter].IsCurrentVersion) {
                            $VersionCounter++
                            Write-Host -ForegroundColor Magenta "`t`tHuidige versie behouden: $($Versions[$VersionCounter].VersionLabel)"
                            Continue
                        }

                        Write-Host -ForegroundColor Cyan "`t Verwijderen van versie: $($Versions[$VersionCounter].VersionLabel)"
                        $Versions[$VersionCounter].DeleteObject()
                    }

                    $Ctx.ExecuteQuery()
                    Write-Host -ForegroundColor Green "`t✅ Versiegeschiedenis opgeschoond voor: $($File.Name)"
                }
            }
            Catch {
                Write-Host -ForegroundColor DarkRed "`t⚠️ Fout bij bestand $($Item.FieldValues["FileLeafRef"]): $($_.Exception.Message)"
                Continue
            }
        }
    }
}
Catch {
    Write-Host -ForegroundColor Red "❌ Fout bij het ophalen van documentbibliotheken: $($_.Exception.Message)"
}
