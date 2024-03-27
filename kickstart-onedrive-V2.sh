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

#!!!!!!!!!!!!!!!!!!! Aan te passen variabele bv "/Users/$loggedInUser/OneDrive - mycompany" !!!!!!!!!!!!!!!!!!!!
oneDriveFolder = "/Users/$loggedInUser/OneDrive - mycompany"


fixlog="/private/var/log/onedrive-kickstart/onedrive-kickstart.log"
readonly fixlog




logging () {
	echo $fixdate": " $1 | tee -a "$fixlog"
}

#Create log
fixdate="$(date +%d%m%Y-%H:%M)"

[[ -d "/private/var/log/onedrive-kickstart" ]] || mkdir "/private/var/log/onedrive-kickstart"



# Check if the OneDrive folder is present

if [ -d $oneDriveFolder ]; then
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