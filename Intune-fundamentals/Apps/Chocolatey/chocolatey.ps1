Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
exit 0
#Best als script

#in Intune install regel:
#   powershell.exe -executionpolicy bypass .\chocolatey.ps1 

#Detection rule:
# C:\ProgramData\
# File or folder: Chocolatey
# File or folder exists
# Associated with 32-bit app on 64:  YES