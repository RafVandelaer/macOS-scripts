#!/bin/zsh

#############################################################################################################
#                                      Created by Raf Vandelaer                                             #
#                                                                                                           #
#                 Script to install the third party tools in Intune.                                        #
#                  This script checks the version of the script and downloads                               #
#                  a newer version if available. Connfig as follows:                                        #
#                       Run script as signed-in user : No                                                   #
#                       Hide script notifications on devices : Yes                                          #
#                       Script frequency : Every week                                                       #
#                       Number of times to retry if script fails : 3                                        #
#                                                                                                           #
#                   Logs can be found in /var/log/intune                                                    #
#                                                                                                           #
#############################################################################################################

#check in the intake document if the customer would like to be possible to get admin rights for 30 min.
#if so, change to following variable to true
isAdminAllowed=true

main() {
    #Main function of this script
    
    #TODO: Privileges app toevoegen + plist !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    #TODO: DOCK privileges, in andere file.
    #ToDo: installomator voor dockutil en desktoppr gebruiken. 

    # Installs the latest release of Installomator from Github
    if [ -f "/usr/local/Installomator/Installomator.sh" ]; then
		logging "installomator installed, checking version..."
        checkAppVersion "installomator" $installomatorRepo

	else 
        logging "Installing installomator"
	    installApp "Installomator" $installomatorRepo
	fi
    #Installing Dockutil, desktoppr, privileges
    installomatorInstall dockutil
    installomatorInstall desktoppr
    installomatorInstall swiftdialog
    if [ "$isAdminAllowed" = true ] ; then
        installomatorInstall privileges
    fi
}

#logging
logging () {
    fixdate="$(date +%d%m%Y-%H:%M)"
	echo $fixdate": " $1 | tee -a "$fixlog"
}
installomatorInstall(){
    appToInstall=$1
   logging "Installing "$appToInstall
    /usr/local/Installomator/Installomator.sh $appToInstall
}
addtoDock (){
     logging "adding "$1" to the dock"
    /usr/local/bin/dockutil --add $1
}

installApp(){
    APP=$1
    repo=$2

    # Download latest release PKG from Github
    curl -s $repo \
    | grep "https*.*pkg" | cut -d : -f 2,3 | tr -d \" \
    | xargs curl -SL --output /tmp/$APP.pkg
    
    # Install PKG to root volume
    installer -pkg /tmp/$APP.pkg -target /
    
    # Cleanup
    rm /tmp/$APP.pkg

}
#checking if app version is newer at github. If so -> Downloading and installing newer version
checkAppVersion(){
    APP=$1
    scriptURL=$2
    #checking old and new MD5 of file
    storedMD5=$(<"$dir/$APP.version")
    newMD5=$(curl -sL $scriptURL |  grep '"tag_name":')
    if [[ "$storedMD5" == "$newMD5" ]]; then
        logging "Same file version on server for $APP, no need to do anything..."
        #if md5 are the same, no need to download again.
    else
        logging "OTHER file version on server for $APP, downloading..."
        #other md5 -> need to download newer script and change the stored MD5
        curl -sL $scriptURL |   grep '"tag_name":' > $dir/$APP.version
        installApp $APP $scriptURL
    fi

}
#base vars
logFolder="/var/log/intune"
dir="/Users/Shared/Lab9Pro/versioncheck"
mkdir $dir
installomatorRepo="https://api.github.com/repos/Installomator/Installomator/releases/latest"

[[ -d $logFolder ]] || mkdir $logFolder
chmod 755 $logFolder
fixlog=$logFolder"/intune-fundamentals-install.log"
touch $fixlog
readonly fixlog
main;