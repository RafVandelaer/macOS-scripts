#!/bin/zsh
toInstall='bbedit, mist-cli'

main() {
	if [ -f /usr/local/Installomator/Installomator.sh ]; then
		echo "Installomator ready"
	else 
	   echo "Installomator not found"
	fi
	[[ -f "${log}" ]] || touch "${log}"
    /usr/local/Installomator/Installomator.sh "$toInstall"
	#/usr/local/Installomator/Installomator.sh $toInstall > $fixlog
	exit 0
}
logFolder="/var/log/intune/"
[[ -d $logFolder ]] || mkdir $logFolder
chmod 775 $logFolder
fixlog=$logFolder"intune-installomator.log"
echo $fixlog
#${logFolder}"
touch $fixlog
readonly fixlog
main;