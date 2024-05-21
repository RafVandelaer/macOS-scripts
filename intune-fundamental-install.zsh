#!/bin/zsh

#############################################################################################################
#                                      Created by Raf Vandelaer                                             #
#                                                                                                           #
#                    #script to install the third party tools in Intune, config as follows:                 #
#                       #Run script as signed-in user : No                                                  #
#                       #Hide script notifications on devices : Yes                                         #
#                       #Script frequency : Not Configured (so it only runs once)                           #
#                       #Number of times to retry if script fails : 3                                       #
#                                                                                                           #
#                   #Logs can be found in /private/var/log/intune                                           #
#                                                                                                           #
#############################################################################################################


main() {
    #Main function of this script
    
    # Installs the latest release of dockutil from Github
    if [[ -f "/usr/local/bin/dockutil" ]]; then
		logging "Dockutil installed and ready"
	else 
        logging "Installing Dockutil"
	    installApp "Dockutil" "https://api.github.com/repos/kcrawford/dockutil/releases/latest"
	fi
    # Installs the latest release of Desktoppr from Github
    if [[ -f "/usr/local/bin/desktoppr" ]]; then
		logging "Desktoppr installed and ready"
	else 
        logging "Installing Desktoppr"
	    installApp "Desktoppr" "https://api.github.com/repos/scriptingosx/desktoppr/releases/latest"
	fi
}

#logging
logging () {
    fixdate="$(date +%d%m%Y-%H:%M)"
	echo $fixdate": " $1 | tee -a "$fixlog"
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


installDockutil(){
    APP=dockutil
    # Download latest release PKG from Github
    curl -s https://api.github.com/repos/kcrawford/dockutil/releases/latest \
    | grep "https*.*pkg" | cut -d : -f 2,3 | tr -d \" \
    | xargs curl -SL --output /tmp/$APP.pkg
    
    # Install PKG to root volume
    installer -pkg /tmp/$APP.pkg -target /
    
    # Cleanup
    rm /tmp/$APP.pkg

}

#base vars
logFolder="/private/var/log/intune"
[[ -d $logFolder ]] || mkdir $logFolder
fixlog=$logFolder"/intune-fundamentals-install.log"
touch $fixlog
readonly fixlog
main;