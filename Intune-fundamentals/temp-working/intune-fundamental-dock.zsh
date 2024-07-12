#!/bin/zsh

#############################################################################################################
#                                      Created by Raf Vandelaer                                             #
#                                                                                                           #
#                    script to configure the macOS dock run as following                                    #
#                       Run script as signed-in user : Yes                                                  #
#                       Hide script notifications on devices : Yes                                          #
#                       Script frequency : Not Configured (so it only runs once)                            #
#                       Number of times to retry if script fails : 3                                        #
#                                                                                                           #
#                                                                                                           #
#############################################################################################################

#Change the following items to add or remove to the dock. 
setDock(){

    $dockutil --remove 'Safari'
    $dockutil --remove 'Mail'
    $dockutil --remove 'Calendar'
    $dockutil --remove 'Contacts'
    $dockutil --remove 'Reminders'
    $dockutil --remove 'Notes'
    $dockutil --remove 'Freeform'
    $dockutil --remove 'Keynote'
    $dockutil --remove 'Numbers'
    $dockutil --remove 'Pages'
    $dockutil --remove 'App Store'
    $dockutil --remove 'FaceTime'
    $dockutil --remove 'TV'
    $dockutil --remove 'Music'
    $dockutil --remove 'System Preferences'

    $dockutil --add "/Applications/Microsoft Outlook.app" $HOME 
    $dockutil --add "/Applications/Microsoft Teams.app" $HOME
    $dockutil --add "/Applications/Microsoft Word.app" $HOME
    $dockutil --add '/Applications/Microsoft Edge.app' $HOME 
    $dockutil --add '/Applications/Microsoft Teams (work or school).app' $HOME 
    $dockutil --add '/Applications/Microsoft Outlook.app' $HOME 
    $dockutil --add '/Applications/Microsoft Excel.app' $HOME 
    $dockutil --add '/Applications/Microsoft PowerPoint.app' $HOME 
    $dockutil --add '/Applications/Microsoft OneNote.app' $HOME 
    $dockutil --add '/Applications/Microsoft OneDrive.app' $HOME 
    $dockutil --add '/Applications/Company Portal.app' $HOME 
    $dockutil --add '/Applications/Microsoft Defender.app' $HOME 
}

#############################################################################################################

main() {
    #Main function of this script
   #Installs the latest release of dockutil from Github
    if [[ -f "/usr/local/bin/dockutil" ]]; then
		logging "Dockutil installed and ready"
	else 
        logging "Installing Dockutil"
	    installApp "Dockutil" "https://api.github.com/repos/kcrawford/dockutil/releases/latest"
	fi
    setDock
   
}

#logging
logging () {
    fixdate="$(date +%d%m%Y-%H:%M)"
	echo $fixdate": " $1 
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
dockutil="/usr/local/bin/dockutil"
loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
echo $HOME
main;