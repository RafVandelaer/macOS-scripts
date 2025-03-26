#!/bin/zsh
#Firstly add the drivers pkg
printShortName="${4}"                           #Name without spaces or special characters
ipAddress="${5}"                                         #IP address
printDriver="${6}"                                        #Path to driver e.g: /Library/Printers/PPDs/Contents/Resources/KONICAMINOLTAC458.gz
printFriendlyName="${7}"                     #Friendly name for in Printer & Scanners panel
#
/usr/sbin/lpadmin -p $printShortName -v lpd://$ipAddress -D "$printFriendlyName" -P $printDriver -o printer-is-shared=false -E
echo Printer was configured.
exit 0