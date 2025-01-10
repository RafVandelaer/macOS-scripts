#!/bin/zsh

#Variables to change
certLocation="/Users/Shared/certificate.pem"


main(){
    loggedInUser=$( echo "show State:/Users/ConsoleUser" | /usr/sbin/scutil | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }' )
    userHome=$(/usr/bin/dscl . read "/Users/$loggedInUser" NFSHomeDirectory | awk '{print $NF}')
    logging "Current user home folder is "$userHome""

    logging "Installing certificate"
    
    sudo security add-trusted-cert \
    -d \
    -r trustRoot \
    -k $userHome/Library/Keychains/login.keychain $certLocation
    exit 0
}


logging () {
    fixdate="$(date +%d%m%Y-%H:%M)"
	echo $fixdate": " $1 | tee -a "$fixlog"
}


#base vars for logging
logFolder="/var/log/intune"
mkdir $dir

[[ -d $logFolder ]] || mkdir $logFolder
chmod 755 $logFolder
fixlog=$logFolder"/intune-certificate-install.log"
touch $fixlog
readonly fixlog

#running main function
main;