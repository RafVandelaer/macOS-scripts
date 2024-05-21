#!/bin/zsh

#############################################################################################################
#                                      Created by Raf Vandelaer                                             #
#                                                                                                           #
#                    script to configure the macOS wallpaper run as following                               #
#                       Run script as signed-in user : Yes                                                  #
#                       Hide script notifications on devices : Yes                                          #
#                       Script frequency : Not Configured (so it only runs once)                            #
#                       Number of times to retry if script fails : 3                                        #
#                                                                                                           #
#                                                                                                           #
#############################################################################################################

#Change the following path to the file which you added in a pkg LOB
wallpaper="/Users/Shared/wallpaper.png"

#############################################################################################################

main() {
    #Main function of this script
    # Installs the latest release of Desktoppr from Github
    if [[ -f "/usr/local/bin/desktoppr" ]]; then
		logging "Desktoppr installed and ready"
	else 
        logging "Installing Desktoppr"
	    installApp "Desktoppr" "https://api.github.com/repos/scriptingosx/desktoppr/releases/latest"
	fi
    #Setting wallpaper 
    #check if file exists
    if [[ -f $wallpaper ]]; then
		logging "Wallpaper file found. Installing"
        /usr/local/bin/desktoppr $wallpaper
	else 
        logging "Wallpaper file not found."
	fi
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
main;