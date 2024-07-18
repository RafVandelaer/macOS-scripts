#!/bin/zsh
function main(){

    log="/var/log/addAppstoDock.log"
    exec &> >(tee -a "$log")
    downloadAndInstallInstallomator
    installomatorInstall "dockutil"
   
    exec 1>&3 3>&-
}
copyDockPlist(){
    cp "/Users/${currentDockUser}/Library/Preferences/com.apple.dock.plist" "/Users/${currentDockUser}/Desktop/dock.plist"
    cp "/Users/${currentDockUser}/Library/Preferences/com.apple.dock.plist" "/Users/${currentDockUser}/Desktop/dock-ref.plist"

    /usr/local/bin/dockutil --remove all --no-restart "/Users/${currentDockUser}/Desktop/dock.plist"

    dockutil --add /Applications/Safari.app --no-restart  "/Users/${currentDockUser}/Desktop/dock.plist"

}

installomatorInstall(){
    appToInstall=$1
   logging "Installing "$appToInstall
    /usr/local/Installomator/Installomator.sh $appToInstall
}
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
	echo "$name check for installation"
	# download URL, version and Expected Team ID
	# Method for GitHub pkg
	gitusername="Installomator"
	gitreponame="Installomator"
	#echo "$gitusername $gitreponame"
	filetype="pkg"
	downloadURL=$(curl -sfL "https://api.github.com/repos/$gitusername/$gitreponame/releases/latest" | awk -F '"' "/browser_download_url/ && /$filetype\"/ { print \$4; exit }")
	if [[ "$(echo $downloadURL | grep -ioE "https.*.$filetype")" == "" ]]; then
		echo "GitHub API failed, trying failover."
		#downloadURL="https://github.com$(curl -sfL "https://github.com/$gitusername/$gitreponame/releases/latest" | tr '"' "\n" | grep -i "^/.*\/releases\/download\/.*\.$filetype" | head -1)"
		downloadURL="https://github.com$(curl -sfL "$(curl -sfL "https://github.com/$gitusername/$gitreponame/releases/latest" | tr '"' "\n" | grep -i "expanded_assets" | head -1)" | tr '"' "\n" | grep -i "^/.*\/releases\/download\/.*\.$filetype" | head -1)"
	fi
	#echo "$downloadURL"
	appNewVersion=$(curl -sLI "https://github.com/$gitusername/$gitreponame/releases/latest" | grep -i "^location" | tr "/" "\n" | tail -1 | sed 's/[^0-9\.]//g')
	#echo "$appNewVersion"
	expectedTeamID="JME5BW3F3R"

	destFile="/usr/local/Installomator/Installomator.sh"
	currentInstalledVersion="$(${destFile} version 2>/dev/null || true)"
	echo "${destFile} version: $currentInstalledVersion"
	if [[ ! -e "${destFile}" || "$currentInstalledVersion" != "$appNewVersion" ]]; then
		echo "$name not found or version not latest."
		echo "${destFile}"
		echo "Installing version ${appNewVersion} ..."
		# Create temporary working directory
		tmpDir="$(mktemp -d || true)"
		echo "Created working directory '$tmpDir'"
		# Download the installer package
		echo "Downloading $name package version $appNewVersion from: $downloadURL"
		installationCount=0
		exitCode=9
		while [[ $installationCount -lt 3 && $exitCode -gt 0 ]]; do
			curlDownload=$(curl -Ls "$downloadURL" -o "$tmpDir/$name.pkg" || true)
			curlDownloadStatus=$(echo $?)
			if [[ $curlDownloadStatus -ne 0 ]]; then
				echo "error downloading $downloadURL, with status $curlDownloadStatus"
				echo "${curlDownload}"
				exitCode=1
			else
				echo "Download $name succes."
				# Verify the download
				teamID=$(spctl -a -vv -t install "$tmpDir/$name.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()' || true)
				echo "Team ID for downloaded package: $teamID"
				# Install the package if Team ID validates
				if [ "$expectedTeamID" = "$teamID" ] || [ "$expectedTeamID" = "" ]; then
					echo "$name package verified. Installing package '$tmpDir/$name.pkg'."
					pkgInstall=$(installer -verbose -dumplog -pkg "$tmpDir/$name.pkg" -target "/" 2>&1)
					pkgInstallStatus=$(echo $?)
					if [[ $pkgInstallStatus -ne 0 ]]; then
						echo "ERROR. $name package installation failed."
						echo "${pkgInstall}"
						exitCode=2
					else
						echo "Installing $name package succes."
						exitCode=0
					fi
				else
					echo "ERROR. Package verification failed for $name before package installation could start. Download link may be invalid."
					exitCode=3
				fi
			fi
			((installationCount++))
			echo "$installationCount time(s), exitCode $exitCode"
			if [[ $installationCount -lt 3 ]]; then
				if [[ $exitCode -gt 0 ]]; then
					echo "Sleep a bit before trying download and install again. $installationCount time(s)."
					echo "Remove $(rm -fv "$tmpDir/$name.pkg" || true)"
					sleep 2
				fi
			else
				echo "Download and install of $name succes."
			fi
		done
		# Remove the temporary working directory
		echo "Deleting working directory '$tmpDir' and its contents."
		echo "Remove $(rm -Rfv "${tmpDir}" || true)"
		# Handle installation errors
		if [[ $exitCode != 0 ]]; then
			echo "ERROR. Installation of $name failed. Aborting."
			caffexit $exitCode
		else
			echo "$name version $appNewVersion installed!"
		fi
	else
		echo "$name version $appNewVersion already found. Perfect!"
	fi

}

currentDockUser=$(echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }')
main