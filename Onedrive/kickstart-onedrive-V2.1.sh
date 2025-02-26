#!/bin/bash

#
# OneDrive kickstart script
#
# Checks if user has set up OneDrive, and if it's running.
#
# If user has set up OneDrive, and it's not running, restarts OneDrive.
#
# Tweaked from: https://github.com/soundsnw/mac-sysadmin-resources/blob/master/extension-attributes/onedrive-syncfailures.sh

# Get logged in user
loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )


#Create log

fixlog="/private/var/log/onedrive-kickstart/onedrive-kickstart.log"
readonly fixlog
fixdate="$(date +%d%m%Y-%H:%M)"
logging () {
	echo $fixdate": " $1 | tee -a "$fixlog"
}

#!!!!!!!!!!!!!!!!!!! Aan te passen variabele bv "/Users/$loggedInUser/OneDrive - mycompany" !!!!!!!!!!!!!!!!!!!!
#oneDriveFolder="/Users/$loggedInUser/OneDrive - mycompany"
#find "/Users/raf.vandelaer@lab9pro.be" -maxdepth 1 -name "OneDrive*" -exec readlink -f {} \; | grep -v -e 'Personal' -e  "Persoonlijk" -e "library" -e "bibliotheken"
onedrivefolder=$(find "/Users/$loggedInUser/" -maxdepth 1 -name "OneDrive*" -exec readlink -f {} \; | grep -v -e 'Personal' -e  "Persoonlijk" -e "library" -e "bibliotheken" | head -n 1)

logging $onedrivefolder



[[ -d "/private/var/log/onedrive-kickstart" ]] || mkdir "/private/var/log/onedrive-kickstart"



# Check if the OneDrive folder is present

if [ -d "$onedrivefolder" ]; then
    logging "User has configured OneDrive."
else
	logging "User hasn't set up OneDrive, aborting."
	exit 1;
fi

# Check if OneDrive is running

if [[ ! $(/usr/bin/pgrep -x "OneDrive") ]]; then
	logging "OneDrive is inactive, restarting client."
	sudo -u $loggedInUser open "/Applications/OneDrive.app"
else
         logging "OneDrive is already running."
fi


exit 0