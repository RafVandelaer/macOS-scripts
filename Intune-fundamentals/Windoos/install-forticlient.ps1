$logDir = 'C:\logs\'
$logFile = 'ForticlientVPN.log'

New-Item -ItemType Directory -Force -Path $logFile
$log = $logDir + $logFile
Start-Transcript -Path $log

$localprograms = choco list
if ($localprograms -like "*forticlientvpn*")
{
    choco upgrade forticlientvpn
}
Else
{
    choco install forticlientvpn -y
}



# Zorg dat het script als administrator wordt uitgevoerd

$regPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels\Company VPN"

# Maak de sleutel aan als die nog niet bestaat
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

# Voeg de waarden toe
Set-ItemProperty -Path $regPath -Name "Description" -Value "" -Type String
Set-ItemProperty -Path $regPath -Name "Server" -Value "xxx:10443" -Type String
Set-ItemProperty -Path $regPath -Name "DATA1" -Value "" -Type String
Set-ItemProperty -Path $regPath -Name "promptusername" -Value 0 -Type DWord
Set-ItemProperty -Path $regPath -Name "promptcertificate" -Value 0 -Type DWord
Set-ItemProperty -Path $regPath -Name "DATA3" -Value "" -Type String
Set-ItemProperty -Path $regPath -Name "ServerCert" -Value "1" -Type String
Set-ItemProperty -Path $regPath -Name "sso_enabled" -Value 1 -Type DWord
Set-ItemProperty -Path $regPath -Name "use_external_browser" -Value 1 -Type DWord

Write-Host "FortiClient VPN registry settings have been applied successfully."



Stop-Transcript
exit 0