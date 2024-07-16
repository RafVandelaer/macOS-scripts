#!/bin/zsh

#############################################################################################################
#                                      Created by Raf Vandelaer                                             #
#                                                                                                           #
#                     *************  One script to rule them all *************                              #
#                                                                                                           #
#                                                                                                           #
#                 Script to install the fundamentals install in Intune.                                     #
#                  This script checks the version of the script and downloads                               #
#                  a newer version if available. Config with the following settings:                        #
#                       Run script as signed-in user : No                                                   #
#                       Hide script notifications on devices : Yes                                          #
#                       Script frequency : Every week                                                       #
#                       Number of times to retry if script fails : 3                                        #
#                                                                                                           #
#                   Logs can be found in /var/log/intune                                                    #
#                                                                                                           #
#############################################################################################################


########################################### Parameters to modify #########################################################

		#check in the intake document if the customer would like to demote the current enduser to standard user (non admin).
		#if so, change the following variable to true, otherwise set to false
		demoteUser=true

		#check in the intake document if the customer would like to be possible to get admin rights for 30 min.
		#if so, change to following variable to true, otherwise set to false
		isAllowedToBecomeAdmin=true

		#Type the labels you want to install on the endpoints. Double check the labels using the link in the following line.
		#you can choose other apps for intel or arm (Apple Mx) architecture. ARM64 = Apple Mx.
		#All the neccesary apps for the fundamentals install are already installed. 
		#https://github.com/Installomator/Installomator/blob/main/Labels.txt

		if [[ $(arch) == "arm64" ]]; then
			items=(microsoftautoupdate theunarchiver microsoftoffice365 microsoftedge microsoftteams microsoftonedrive microsoftdefender microsoftcompanyportal displaylinkmanager)
			# displaylinkmanager
		else
			items=(microsoftautoupdate theunarchiver microsoftoffice365 microsoftedge microsoftteams microsoftonedrive microsoftdefender microsoftcompanyportal)
		fi

	#Installomator variables, here you can configure which labels need to be updated with auto updater. Alternativly copy paste from above.
		interactiveMode="${4:="2"}"                             # Parameter 4: Interactive Mode [ 0 (Completely Silent) | 1 (Silent Discovery, Interactive Patching) | 2 (Full Interactive) (default) ]
		ignoredLabels="${5:=""}"                                # Parameter 5: A space-separated list of Installomator labels to ignore (i.e., "microsoft* googlechrome* jamfconnect zoom* 1password* firefox* swiftdialog")
		requiredLabels="${6:=""}"                               # Parameter 6: A space-separated list of required Installomator labels (i.e., "firefoxpkg_intl")
		optionalLabels="${7:=""}"                               # Parameter 7: A space-separated list of optional Installomator labels (i.e., "renew") ** Does not support wildcards **
		#is overrun below
		installomatorOptions="${8:-""}"                         # Parameter 8: A space-separated list of options to override default Installomator options (i.e., BLOCKING_PROCESS_ACTION=prompt_user NOTIFY=silent LOGO=appstore)
		maxDeferrals="${9:-"3"}" 

##################################################################################################


installomatorOptions="NOTIFY=silent BLOCKING_PROCESS_ACTION=ignore INSTALL=force IGNORE_APP_STORE_APPS=yes LOGGING=REQ"

# DEPNotify display settings, change as desired
title="Installeren van apps"
message="Gelieve even te wachten, de apps worden gedownload en geïnstalleerd. U kan het toesel in beperkte mate gebruiken."
endMessage="Installatie klaar! Custom aangevraagde apps worden later geïnstalleerd."
errorMessage="Er was een probleem met de installatie van de apps. Gelieve IT te contacteren."



# MARK: Variables
instance="Lab9 Pro" # Name of used instance
LOGO="microsoft"
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
scriptVersion="9.11"
# Command-file to DEPNotify
DEPNOTIFY_LOG="/var/tmp/depnotify.log"
firstrun="/Users/Shared/Lab9Pro/firstrun"
wallpaperIsSet="/Users/Shared/Lab9Pro/wallpaperIsSet"
# Counters
errorCount=0

countLabels=${#items[@]}
#vars for our helper script
dir="/Users/Shared/Lab9Pro/auto-app-updater"
wallpaper="/Users/Shared/Lab9Pro/company-wallpaper.jpg"
scriptname="/auto-app-updater.zsh"
fullpath=$dir$scriptname
scriptURL="https://raw.githubusercontent.com/Lab9Pro-AL/Intune/main/auto-app-updater/auto-app-updater.zsh"

mkdir $dir

main() {
    #Main function of this script

	#checking if first run, if so we deploy all software and run DEPnotify
	# Installs the latest release of Installomator from Github
    if [ -f $firstrun ]; then
		#if not firstrun, updating software. 
		#checking if file exists
		logging "Not first run so we need to run auto-updater. Check autopatch-lab9pro.log for more info"
		if [ -f "$dir/auto-app-updater.md5" ]; then
			#checking old and new MD5 of file
			storedMD5=$(<"$dir/auto-app-updater.md5")
			newMD5=$(curl -sL $scriptURL | md5)
			if [[ "$storedMD5" == "$newMD5" ]]; then
				logging "Same file on server, not downloading..."
				#if md5 are the same, no need to download again.
				#Execute the script
				$dir/auto-app-updater.zsh null null null $interactiveMode $ignoredLabels $requiredLabels $optionalLabels $installomatorOptions $maxDeferrals
			else
				#other md5 -> need to download newer script and change the stored MD5
				logging "Other version of auto-patch, let's go."
				downloadAndRunAutoAppUpdater
			fi
		
		else 
			#if  no md5 available -> creating for future checks, downloading and running script
		downloadAndRunAutoAppUpdater
		fi
		#checking if wallpaper is previously set, if not... checking if file is available and if so, setting.
		checkAndSetWallpaper

	#if first run, we need to install all the software first and run the DEPNotify	
	else 
		logging "This is first run... Installing all apps and running DEPNotify."
		
		touch $firstrun
		#installing basic needs so we can show user the progress
        downloadAndInstallInstallomator
		installomatorInstall depnotify
		#adding items to list to install
		items+=("dockutil")
		items+=("desktoppr")
		items+=("swiftdialog")
		items+=("dialog")
		#running depnotify asap
		logging "configuring DEPNotify"
		configDEP
		logging "Starting DEPNotify"
		startDEPNotify
		logging "Items to install: ${items[*]}"
		#OLD
		#installomatorInstall dockutil
		#installomatorInstall desktoppr
		#installomatorInstall swiftdialog
		#installomatorInstall dialog
		
		#if neccesary, install privileges app and it's helper-tool
		if [ "$isAllowedToBecomeAdmin" = true ] ; then
			installomatorInstall privileges
			install-privileges-helper
		fi
		logging "Running DEPNotify and installing all apps. Check /var/log/intune/Installomator-DEP.log"
		runDEP
		logging "checking if wallpaper is already available."
		checkAndSetWallpaper
		logging "demoting user if configured"
		#demoteUserToStandard
		logging "All done for this round"
	
	fi
	
    exit 0
}
# function demoteUserToStandard{
# 	currentAdminUser=$(ls -l /dev/console | awk '{ print $3 }')

#       if [[ $currentAdminUser != "sifi" ]]; then
#         IsUserAdmin=$(id -G $currentAdminUser| grep 80)
#             if [[ -n "$IsUserAdmin" ]]; then
# 				echo "demoting $currentAdminUser to standard user"
#               /usr/sbin/dseditgroup -o edit -n /Local/Default -d $currentAdminUser -t "user" "admin"
#               exit 0
#             else
#                 echo "$currentAdminUser already standard user..."
#             fi
#       fi
# }
function checkAndSetWallpaper  () {
	#checking if wallpaper was already set
	if [[ ! -f $wallpaperIsSet ]]; then
		#if not set, setting once, if file is available
		if [[ -f $wallpaper ]]; then
			logging "wallpaper available and not yet configured, configuring..."
			currentDesktopUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
			sudo -u "$currentDesktopUser" /usr/local/bin/desktoppr $wallpaper
			touch $wallpaperIsSet
		else
			logging "wallpaper not yet available or never configured"
		fi
	fi
	
}
function downloadAndRunAutoAppUpdater () {
    echo "Downloading new file and executing."
     curl -sL $scriptURL | md5 > $dir/auto-app-updater.md5
    # Download the script from the given URL
     curl -o $fullpath $scriptURL 
    # Make the script executable
     chmod +x $fullpath
    #Execute the script
      $dir/auto-app-updater.zsh null null null $interactiveMode $ignoredLabels $requiredLabels $optionalLabels $installomatorOptions $maxDeferrals

}

#logging
logging () {
    fixdate="$(date +%d%m%Y-%H:%M)"
	echo $fixdate": " $1 | tee -a "$fixlog"
}
printlog(){
    timestamp=$(date +%F\ %T)
    if [[ "$(whoami)" == "root" ]]; then
        echo "$timestamp :: $label : $1" | tee -a $log_location
    else
        echo "$timestamp :: $label : $1"
    fi
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
configDEP(){
	# MARK: Constants, logging and caffeinate
		log_message="$instance: Installomator 1st with DEPNotify, v$scriptVersion"
		label="1st-v$scriptVersion"

		log_location=$logFolder"/Installomator-DEP.log"

		printlog "[LOG-BEGIN] ${log_message}"

		# Internet check
		if [[ "$(nc -z -v -G 10 1.1.1.1 53 2>&1 | grep -io "succeeded")" != "succeeded" ]]; then
			printlog "ERROR. No internet connection, we cannot continue."
			exit 90
		fi

		# No sleeping
		/usr/bin/caffeinate -d -i -m -u &
		caffeinatepid=$!
		printlog "Total installations: $countLabels"

		# Microsoft Endpoint Manager (Intune)
        LOGO_PATH="/Library/Intune/Microsoft Intune Agent.app/Contents/Resources/AppIcon.icns"
		if [[ ! -a "${LOGO_PATH}" ]]; then
			printlog "ERROR in LOGO_PATH '${LOGO_PATH}', setting Mac App Store."
			if [[ $(/usr/bin/sw_vers -buildVersion) > "19" ]]; then
				LOGO_PATH="/System/Applications/App Store.app/Contents/Resources/AppIcon.icns"
			else
				LOGO_PATH="/Applications/App Store.app/Contents/Resources/AppIcon.icns"
			fi
		fi
		printlog "LOGO: $LOGO - LOGO_PATH: $LOGO_PATH"
		# MARK: Functions
		printlog "depnotify_command function"
		echo "" > $DEPNOTIFY_LOG || true
		depnotify_command "Status: Configureren van items, even geduld."

		# MARK: Install DEPNotify
		cmdOutput="$( ${destFile} depnotify LOGO=$LOGO NOTIFY=silent BLOCKING_PROCESS_ACTION=ignore LOGGING=WARN || true )"
		exitStatus="$( echo "${cmdOutput}" | grep --binary-files=text -i "exit" | tail -1 | sed -E 's/.*exit code ([0-9]).*/\1/g' || true )"
		printlog "DEPNotify install result: $exitStatus"
}
runDEP(){
			# Check before running
		echo "LOGO: $LOGO"
		if [[ -z $LOGO ]]; then
			echo "ERROR: LOGO variable empty. Fatal problem. Exiting."
			exit 1
		fi
		case $LOGO in
			addigy|microsoft)
				conditionFile="/var/db/.Installomator1stDone"
				# Addigy and Microsoft Endpoint Manager (Intune) need a check for a touched file
				if [ -e "$conditionFile" ]; then
					echo "$conditionFile exists, so we exit."
					exit 0
				else
					echo "$conditionFile not found, so we continue…"
				fi
				;;
		esac

		

		# MARK: Installations with DEPNotify
		itemName=""
		errorLabels=""
		((countLabels++))
		((countLabels--))
		printlog "$countLabels labels to install"

		#aangepast Raf 12/07
		#startDEPNotify

		for item in "${items[@]}"; do
			# Check if DEPNotify is running and try open it if not
			if ! pgrep -xq "DEPNotify"; then
				startDEPNotify
			fi
			itemName=$( ${destFile} ${item} RETURN_LABEL_NAME=1 LOGGING=REQ INSTALL=force | tail -1 || true )
			if [[ "$itemName" != "#" ]]; then
				depnotify_command "Status: installeren van $itemName…"
			else
				depnotify_command "Status: installeren van $item…"
			fi
			printlog "$item $itemName"
			cmdOutput="$( ${destFile} ${item} LOGO=$LOGO ${installomatorOptions} || true )"
			#cmdOutput="2022-05-19 13:20:45 : REQ   : installomator : ################## End Installomator, exit code 0"
			exitStatus="$( echo "${cmdOutput}" | grep --binary-files=text -i "exit" | tail -1 | sed -E 's/.*exit code ([0-9]).*/\1/g' || true )"
			if [[ ${exitStatus} -eq 0 ]] ; then
				printlog "${item} succesfully installed."
				warnOutput="$( echo "${cmdOutput}" | grep --binary-files=text "WARN" || true )"
				printlog "$warnOutput"
			else
				printlog "Error installing ${item}. Exit code ${exitStatus}"
				#printlog "$cmdOutput"
				errorOutput="$( echo "${cmdOutput}" | grep --binary-files=text -i "error" || true )"
				printlog "$errorOutput"
				((errorCount++))
				errorLabels="$errorLabels ${item}"
			fi
			((countLabels--))
			itemName=""
		done

		# MARK: Finishing
		# Prevent re-run of script if conditionFile is set
		if [[ ! -z "$conditionFile" ]]; then
			printlog "Touching condition file so script will not run again"
			touch "$conditionFile" || true
			printlog "$(ls -al "$conditionFile" || true)"
		fi

		# Show error to user if any
		printlog "Errors: $errorCount"
		if [[ $errorCount -ne 0 ]]; then
			errorMessage="${errorMessage} Total errors: $errorCount"
			message="$errorMessage"
			displayDialog &
			endMessage="$message"
			printlog "errorLabels: $errorLabels"
		fi

		depnotify_command "Command: MainText: $endMessage"
		depnotify_command "Command: Quit: $endMessage"

		sleep 1
		printlog "Remove $(rm -fv $DEPNOTIFY_LOG || true)"

		printlog "Ending"
		caffexit $errorCount

}
caffexit () {
    kill "$caffeinatepid" || true
    printlog "[LOG-END] Status $1"
    exit $1
}
function depnotify_command(){
    printlog "DEPNotify-command: $1"
    echo "$1" >> $DEPNOTIFY_LOG || true
}

function startDEPNotify() {
    currentUser="$(stat -f "%Su" /dev/console)"
    currentUserID=$(id -u "$currentUser")
    launchctl asuser $currentUserID open -a "/Applications/Utilities/DEPNotify.app/Contents/MacOS/DEPNotify" --args -path "$DEPNOTIFY_LOG" || true # --args -fullScreen
    sleep 5
    depnotify_command "Command: KillCommandFile:"
    depnotify_command "Command: MainTitle: $title"
    depnotify_command "Command: Image: $LOGO_PATH"
    depnotify_command "Command: MainText: $message"
    depnotify_command "Command: Determinate: $countLabels"
}

# Notify the user using AppleScript
function displayDialog(){
    currentUser="$(stat -f "%Su" /dev/console)"
    currentUserID=$(id -u "$currentUser")
    if [[ "$currentUser" != "" ]]; then
        launchctl asuser $currentUserID sudo -u $currentUser osascript -e "button returned of (display dialog \"$message\" buttons {\"OK\"} default button \"OK\" with icon POSIX file \"$LOGO_PATH\")" || true
    fi
}

install-privileges-helper(){
#https://travellingtechguy.blog/sap-privileges-app/

        exitCode=0

        helperPath="/Applications/Privileges.app/Contents/XPCServices/PrivilegesXPC.xpc/Contents/Library/LaunchServices/corp.sap.privileges.helper"

        if [[ -f "$helperPath" ]]; then

            # create the target directory if needed
            if [[ ! -d "/Library/PrivilegedHelperTools" ]]; then
                /bin/mkdir -p "/Library/PrivilegedHelperTools"
                /bin/chmod 755 "/Library/PrivilegedHelperTools"
                /usr/sbin/chown -R root:wheel "/Library/PrivilegedHelperTools"
            fi
            
            # move the privileged helper into place
            /bin/cp -f "$helperPath" "/Library/PrivilegedHelperTools"
            
            if [[ $? -eq 0 ]]; then
                /bin/chmod 755 "/Library/PrivilegedHelperTools/corp.sap.privileges.helper"

                # create the launchd plist
                helperPlistPath="/Library/LaunchDaemons/corp.sap.privileges.helper.plist"
            
                /bin/cat > "$helperPlistPath" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>corp.sap.privileges.helper</string>
    <key>MachServices</key>
    <dict>
        <key>corp.sap.privileges.helper</key>
        <true/>
    </dict>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/corp.sap.privileges.helper</string>
    </array>
</dict>
</plist>
EOF

                /bin/chmod 644 "$helperPlistPath"
                
                # load the launchd plist only if installing on the boot volume
                    /bin/launchctl bootstrap system "$helperPlistPath"
                
                # restart the Dock if Privileges is in there. This ensures proper loading
                # of the (updated) Dock tile plug-in
                
                # get the currently logged-in user and go ahead if it's not root
                currentUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print  }')

                if [[ -n "$currentUser" && "$currentUser" != "root" ]]; then
                    if [[ -n $(/usr/bin/sudo -u "$currentUser" /usr/bin/defaults read com.apple.dock "persistent-apps" | /usr/bin/grep "/Applications/Privileges.app") ]]; then
                        /usr/bin/killall Dock
                    fi
                fi
                
                # make sure PrivilegesCLI can be accessed without specifying the full path
                echo "/Applications/Privileges.app/Contents/Resources" > "/private/etc/paths.d/PrivilegesCLI"

            else
                exitCode=1
            fi
        else
            exitCode=1
        fi


}
#to install installomator from https://github.com/Installomator/Installomator/blob/main/MDM/Installomator%201st%20Auto-install%20DEPNotify.sh
function downloadAndInstallInstallomator {
	######################################################################
	#
	#  This script made by Søren Theilgaard
	#  https://github.com/Theile
	#  Twitter and MacAdmins Slack: @theilgaard
	#
	#  Some functions and code from Installomator:
	#  https://github.com/Installomator/Installomator
	#
	######################################################################
	# MARK: Install Installomator
	name="Installomator"
	printlog "$name check for installation"
	# download URL, version and Expected Team ID
	# Method for GitHub pkg
	gitusername="Installomator"
	gitreponame="Installomator"
	#printlog "$gitusername $gitreponame"
	filetype="pkg"
	downloadURL=$(curl -sfL "https://api.github.com/repos/$gitusername/$gitreponame/releases/latest" | awk -F '"' "/browser_download_url/ && /$filetype\"/ { print \$4; exit }")
	if [[ "$(echo $downloadURL | grep -ioE "https.*.$filetype")" == "" ]]; then
		printlog "GitHub API failed, trying failover."
		#downloadURL="https://github.com$(curl -sfL "https://github.com/$gitusername/$gitreponame/releases/latest" | tr '"' "\n" | grep -i "^/.*\/releases\/download\/.*\.$filetype" | head -1)"
		downloadURL="https://github.com$(curl -sfL "$(curl -sfL "https://github.com/$gitusername/$gitreponame/releases/latest" | tr '"' "\n" | grep -i "expanded_assets" | head -1)" | tr '"' "\n" | grep -i "^/.*\/releases\/download\/.*\.$filetype" | head -1)"
	fi
	#printlog "$downloadURL"
	appNewVersion=$(curl -sLI "https://github.com/$gitusername/$gitreponame/releases/latest" | grep -i "^location" | tr "/" "\n" | tail -1 | sed 's/[^0-9\.]//g')
	#printlog "$appNewVersion"
	expectedTeamID="JME5BW3F3R"

	destFile="/usr/local/Installomator/Installomator.sh"
	currentInstalledVersion="$(${destFile} version 2>/dev/null || true)"
	printlog "${destFile} version: $currentInstalledVersion"
	if [[ ! -e "${destFile}" || "$currentInstalledVersion" != "$appNewVersion" ]]; then
		printlog "$name not found or version not latest."
		printlog "${destFile}"
		printlog "Installing version ${appNewVersion} ..."
		# Create temporary working directory
		tmpDir="$(mktemp -d || true)"
		printlog "Created working directory '$tmpDir'"
		# Download the installer package
		printlog "Downloading $name package version $appNewVersion from: $downloadURL"
		installationCount=0
		exitCode=9
		while [[ $installationCount -lt 3 && $exitCode -gt 0 ]]; do
			curlDownload=$(curl -Ls "$downloadURL" -o "$tmpDir/$name.pkg" || true)
			curlDownloadStatus=$(echo $?)
			if [[ $curlDownloadStatus -ne 0 ]]; then
				printlog "error downloading $downloadURL, with status $curlDownloadStatus"
				printlog "${curlDownload}"
				exitCode=1
			else
				printlog "Download $name succes."
				# Verify the download
				teamID=$(spctl -a -vv -t install "$tmpDir/$name.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()' || true)
				printlog "Team ID for downloaded package: $teamID"
				# Install the package if Team ID validates
				if [ "$expectedTeamID" = "$teamID" ] || [ "$expectedTeamID" = "" ]; then
					printlog "$name package verified. Installing package '$tmpDir/$name.pkg'."
					pkgInstall=$(installer -verbose -dumplog -pkg "$tmpDir/$name.pkg" -target "/" 2>&1)
					pkgInstallStatus=$(echo $?)
					if [[ $pkgInstallStatus -ne 0 ]]; then
						printlog "ERROR. $name package installation failed."
						printlog "${pkgInstall}"
						exitCode=2
					else
						printlog "Installing $name package succes."
						exitCode=0
					fi
				else
					printlog "ERROR. Package verification failed for $name before package installation could start. Download link may be invalid."
					exitCode=3
				fi
			fi
			((installationCount++))
			printlog "$installationCount time(s), exitCode $exitCode"
			if [[ $installationCount -lt 3 ]]; then
				if [[ $exitCode -gt 0 ]]; then
					printlog "Sleep a bit before trying download and install again. $installationCount time(s)."
					printlog "Remove $(rm -fv "$tmpDir/$name.pkg" || true)"
					sleep 2
				fi
			else
				printlog "Download and install of $name succes."
			fi
		done
		# Remove the temporary working directory
		printlog "Deleting working directory '$tmpDir' and its contents."
		printlog "Remove $(rm -Rfv "${tmpDir}" || true)"
		# Handle installation errors
		if [[ $exitCode != 0 ]]; then
			printlog "ERROR. Installation of $name failed. Aborting."
			caffexit $exitCode
		else
			printlog "$name version $appNewVersion installed!"
		fi
	else
		printlog "$name version $appNewVersion already found. Perfect!"
	fi

}
#base vars
logFolder="/var/log/intune"
dir="/Users/Shared/Lab9Pro"
mkdir $dir

[[ -d $logFolder ]] || mkdir $logFolder
chmod 755 $logFolder
fixlog=$logFolder"/intune-fundamentals-install.log"
touch $fixlog
readonly fixlog
main;