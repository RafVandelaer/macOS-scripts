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

        #With this check, you enable debug mode which overrides the ADE check. This is only to be used in test environments.
        debugEnrollment=1


		#check in the intake document if the customer would like to demote the current enduser to standard user (non admin).
		#if so, change the following variable to 1, otherwise set to 0.
		demoteUser=0

		#check in the intake document if the customer would like to be possible to get admin rights for 30 min.
		#if so, change to following variable to 1, otherwise set to 0.
		isAllowedToBecomeAdmin=1

		#Type the labels you want to install on the endpoints. Double check the labels using the link in the following line.
		#you can choose other apps for intel or arm (Apple Mx) architecture. ARM64 = Apple Mx.
		#All the neccesary apps for the fundamentals install are already installed. 
		#https://github.com/Installomator/Installomator/blob/main/Labels.txt
		if [[ $(arch) == "arm64" ]]; then
			items=( microsoftofficebusinesspro microsoftedge microsoftonedrive microsoftdefender microsoftcompanyportal )
			#items=(microsoftdefender )
			# displaylinkmanager
		else
			#items=(microsoftdefender )
			items=( microsoftofficebusinesspro microsoftedge microsoftonedrive microsoftdefender microsoftcompanyportal)
		fi

		#if the Dock needs to be changed, this should be 1. If the dock should stay as is, change it to 0.
		#Most of the times this will be 1
		changeDock=1

		#Only if the variable above is set to 1, will the following variable have effect. If this is set to 1, all the existing dock items will be removed
		#Check the intake document of the customer
		removeAllDockItems=1

		#Check in the intake document which items the customer wants to add to the dock. Standard Apple Items are being removed. 
		#All Microsoft items should be contained. DO NOT FORGET THE .APP extension!!!!!!!!!!!!!!!!!!!!!!
            dockitems=(
                '/Applications/Microsoft Outlook.app'
                '/Applications/Microsoft Edge.app'
                '/Applications/Microsoft Teams.app'
                '/Applications/Microsoft Word.app'
                '/Applications/Microsoft Excel.app'
                '/Applications/System Settings.app'
                )

# Installomator auto-updater parameters (can be overridden by Intune script parameters 4..9)
interactiveMode="${4:="1"}"
ignoredLabels="${5:=""}"
requiredLabels="${6:=""}"
optionalLabels="${7:=""}"
installomatorOptions="${8:-""}"
maxDeferrals="${9:-"3"}"

##################################################################################################

# ===== SwiftDialog UI i.p.v. DEPNotify =====
title="Installeren van apps"
message="Gelieve even te wachten, de apps worden gedownload en geïnstalleerd. U kan het toestel in beperkte mate gebruiken."
endMessage="Installatie klaar! Custom aangevraagde apps worden later geïnstalleerd."
errorMessage="Er was een probleem met de installatie van de apps. Gelieve IT te contacteren."

# MARK: Variables
instance="Lab9 Pro"
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin
scriptVersion="9.13-swiftdialog"

# SwiftDialog command-file & binary
DIALOG_CMD_FILE="/var/tmp/dialog-setup.log"
DIALOG_BIN="/usr/local/bin/dialog"

# Shared and helper
sharedDir="/Users/Shared/Lab9Pro"
helperDir="$sharedDir/auto-app-updater"
wallpaper="$sharedDir/company-wallpaper.jpg"
helperScriptName="/auto-app-updater.zsh"
helperFullPath="${helperDir}${helperScriptName}"
helperScriptURL="https://raw.githubusercontent.com/Lab9Pro-AL/Intune/main/auto-app-updater/auto-app-updater.zsh"

# Counters
errorCount=0
countLabels=${#items[@]}

# Logging
logFolder="/var/log/intune"
[[ -d $logFolder ]] || mkdir -p "$logFolder"
chmod 755 "$logFolder"
fixlog="$logFolder/intune-fundamentals-install.log"
touch "$fixlog"
readonly fixlog
log_location="$logFolder/Installomator-Dialog.log"
label="1st-v$scriptVersion"

# Installomator global options (sane defaults)
installomatorOptions="NOTIFY=silent BLOCKING_PROCESS_ACTION=ignore INSTALL=force IGNORE_APP_STORE_APPS=yes LOGGING=REQ"

# Ensure dirs
mkdir -p "$sharedDir" "$helperDir"

#################################### Notifications profile for SwiftDialog #######################
# Installeert automatisch een meldingen-profiel zodat SwiftDialog banners/sound/badges mag tonen.
ensure_swiftdialog_notifications_profile() {
    local profile_id="be.jbits.notifications.swiftdialog"
    local tmp_profile="/var/tmp/${profile_id}.mobileconfig"

    if profiles list -type configuration 2>/dev/null | grep -q "$profile_id"; then
        printlog "SwiftDialog notifications profile already present ($profile_id)."
        return 0
    fi

    cat > "$tmp_profile" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key>
      <string>com.apple.notificationsettings</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>PayloadIdentifier</key>
      <string>be.jbits.notifications.swiftdialog.payload</string>
      <key>PayloadUUID</key>
      <string>3E4A6F9C-8C7A-4D3E-9E3B-9C8C3A7A1B21</string>
      <key>PayloadDisplayName</key>
      <string>SwiftDialog Notifications</string>
      <key>NotificationSettings</key>
      <array>
        <dict>
          <key>BundleIdentifier</key>
          <string>au.csiro.SwiftDialog</string>
          <key>Enabled</key>
          <true/>
          <key>AlertType</key>
          <integer>2</integer> <!-- 1=none, 2=banners, 3=alerts -->
          <key>ShowInNotificationCenter</key>
          <true/>
          <key>ShowInLockScreen</key>
          <true/>
          <key>BadgeEnabled</key>
          <true/>
          <key>SoundEnabled</key>
          <true/>
          <key>CriticalAlertEnabled</key>
          <false/>
          <key>GroupingType</key>
          <integer>0</integer> <!-- 0=automatic -->
        </dict>
      </array>
    </dict>
  </array>
  <key>PayloadDisplayName</key>
  <string>SwiftDialog - Notifications</string>
  <key>PayloadIdentifier</key>
  <string>be.jbits.notifications.swiftdialog</string>
  <key>PayloadOrganization</key>
  <string>Jbits</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>F5E2C9AB-7A41-47E6-9D7E-6A3D9C1F4B55</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>
EOF

    printlog "Installing SwiftDialog notifications profile..."
    /usr/bin/profiles -I -F "$tmp_profile" 2>&1 | tee -a "$log_location"
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        printlog "Failed to install SwiftDialog notifications profile (rc=$rc). Continuing without."
    else
        printlog "SwiftDialog notifications profile installed."
    fi
    rm -f "$tmp_profile" 2>/dev/null || true
}

############################################### Main #############################################
main() {
    # Bepaal huidige console user + home
    currentUser="$(stat -f "%Su" /dev/console)"
    userHome="$(dscl . -read /Users/"$currentUser" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    [[ -z "$userHome" ]] && userHome="/Users/$currentUser"

    # Paden
    userLab9Dir="$userHome/Lab9Pro"
    firstrunUser="$userLab9Dir/firstrun"           # nieuwe/definitieve locatie
    sharedFirstrun="/Users/Shared/Lab9Pro/firstrun" # legacy locatie

    # Zorg dat user-map bestaat
    mkdir -p "$userLab9Dir"

    # === LEGACY → USER MIGRATIE VAN 'firstrun' ===
    # Als legacy marker bestaat, kopieer dan naar user-locatie en verwijder legacy
    if [[ -f "$sharedFirstrun" ]]; then
        if [[ ! -f "$firstrunUser" ]]; then
            logging "Legacy firstrun gevonden in Shared. Migreren naar $firstrunUser…"
            # probeer met 'install -p' (preserve timestamps), val terug op 'cp -p'
            /usr/bin/install -p "$sharedFirstrun" "$firstrunUser" 2>/dev/null || cp -p "$sharedFirstrun" "$firstrunUser"
            chmod 644 "$firstrunUser" 2>/dev/null || true
        else
            logging "Zowel legacy als user firstrun aanwezig; user-variant behoudt de waarheid."
        fi
        rm -f "$sharedFirstrun" 2>/dev/null || true
    fi

    # ==== Vanaf hier enkel nog met $firstrunUser werken ====

    # ADE check + tijdelijke bypass (verwijder '|| true' om echte check te forceren)
    isDEP="$(profiles status -type enrollment | grep 'DEP')"
    if [[ $isDEP == *"Yes"* || $debugEnrollment == 1 ]]; then
        logging "Proceeding (DEP check passed of bypass actief)."
        until pgrep -fq "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"; do
            delay=$(( RANDOM % 50 + 10 ))
            echo "$(date) |  + Dock not running, waiting [$delay] seconds"
            sleep $delay
        done
        logging "Dock is here, lets carry on"

        if [[ -f "$firstrunUser" ]]; then
            logging "Not first run (user firstrun bestaat) -> auto-updater."
            runAutoUpdater
            checkAndSetWallpaper
        else
            logging "First run... Installing all apps and running SwiftDialog."
            : > "$firstrunUser"   # maak user-marker aan

            downloadAndInstallInstallomator

            # Tools die we nodig hebben
            items+=("dockutil" "desktoppr" "swiftdialog")
            ((countLabels+=3))

            # Installeer SwiftDialog vooraf en zet meldingen-profiel
            installomatorInstall swiftdialog
            ensure_swiftdialog_notifications_profile

            # Start UI (geen OK-knop tijdens installatie)
            configDialog
            startDialog
            logging "Items (${#items[@]}) to install: ${items[*]}"
            runDialogInstallations

            # Optioneel: Privileges
            if [[ $isAllowedToBecomeAdmin -eq 1 ]] ; then
                installomatorInstall privileges2
                install-privileges-helper
                dockitems+=("/Applications/Privileges.app")
            fi

            checkAndSetWallpaper
            demoteUserToStandard $demoteUser

            if [[ $changeDock -eq 1 ]] ; then
                logging "Customizing dock..."
                createDockV2
            fi

            endDialog
            logging "All done for now"
        fi
    else
        logging "No DEP enrollment. Skipping..."
    fi

    caffexit 0
}


############################################### Dock ###############################################
createDockV2(){
    currentDockUser=$(echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }')
    tmpDock=/var/tmp/dock.plist
    originalDock="/Users/${currentDockUser}/Library/Preferences/com.apple.dock.plist"
    cp "$originalDock" "$tmpDock" 2>/dev/null

    if [[ $removeAllDockItems -eq 1 ]] ; then
        logging "Removing all dock items..."
        /usr/local/bin/dockutil --remove all --no-restart "$tmpDock"
    fi

    for item in "${dockitems[@]}"; do
        /usr/local/bin/dockutil -v --add "$item" --no-restart "$tmpDock"
    done

    cp -f "$tmpDock" "$originalDock" 2>/dev/null
    killall -KILL Dock 2>/dev/null
}

############################################### User demote ########################################
demoteUserToStandard () {
    if [[ $demoteUser -eq 1 ]]; then
        currentAdminUser="$(stat -f "%Su" /dev/console)"
        dseditgroup -o edit -d "$currentAdminUser" -t user admin
        errcode=$?
        if [[ "$errcode" -ne 0 ]]; then
            logging "couldn't demote user to standard..."
        else
            logging "Admin rights revoked for user $currentAdminUser"
            dialog_command "progresstext: Adminrechten intrekken voor gebruiker $currentAdminUser"
        fi
    else
        logging "No demoting needed (demoteUser=$demoteUser)"
    fi
}

############################################### Wallpaper #########################################
wallpaperIsSet="/Users/Shared/Lab9Pro/wallpaperIsSet"
checkAndSetWallpaper() {
    currentDesktopUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
    if [[ ! -f $wallpaperIsSet ]]; then
        if [[ -f $wallpaper ]]; then
            md5 -q "$wallpaper" > "$wallpaperIsSet"
            logging "Setting wallpaper (first time)..."
            sudo -u "$currentDesktopUser" /usr/local/bin/desktoppr "$wallpaper"
            dialog_command "progresstext: Achtergrond instellen"
        else
            logging "Wallpaper not available yet."
        fi
    else
        logging "Wallpaper already set, checking if newer..."
        storedMD5=$(<"$wallpaperIsSet")
        newMD5=$(md5 -q "$wallpaper" 2>/dev/null || echo "")
        if [[ -n "$newMD5" && "$storedMD5" != "$newMD5" ]]; then
            sudo -u "$currentDesktopUser" /usr/local/bin/desktoppr "$wallpaper"
            md5 -q "$wallpaper" > "$wallpaperIsSet"
            logging "Wallpaper updated."
        else
            logging "Wallpaper unchanged."
        fi
    fi
}

############################################### Auto-updater ######################################
runAutoUpdater () {
    if [[ -f "$helperDir/auto-app-updater.md5" ]]; then
        storedMD5=$(<"$helperDir/auto-app-updater.md5")
        newMD5=$(curl -sL "$helperScriptURL" | md5)
        if [[ "$storedMD5" == "$newMD5" ]]; then
            logging "Same auto-updater on server, not downloading."
            "$helperFullPath" null null null $interactiveMode $ignoredLabels $requiredLabels $optionalLabels $installomatorOptions $maxDeferrals
        else
            logging "Newer auto-updater found, downloading."
            downloadAndRunAutoAppUpdater
        fi
    else
        downloadAndRunAutoAppUpdater
    fi
}

downloadAndRunAutoAppUpdater () {
    echo "Downloading new auto-updater and executing."
    curl -sL "$helperScriptURL" | md5 > "$helperDir/auto-app-updater.md5"
    curl -sfLo "$helperFullPath" "$helperScriptURL"
    chmod +x "$helperFullPath"
    "$helperFullPath" null null null $interactiveMode $ignoredLabels $requiredLabels $optionalLabels $installomatorOptions $maxDeferrals
}

############################################### Logging utils #####################################
logging () {
    fixdate="$(date +%d%m%Y-%H:%M)"
    echo "$fixdate: $1" | tee -a "$fixlog"
}
printlog(){
    timestamp=$(date +%F\ %T)
    if [[ "$(whoami)" == "root" ]]; then
        echo "$timestamp :: $label : $1" | tee -a "$log_location"
    else
        echo "$timestamp :: $label : $1"
    fi
}

############################################### Installomator wrap ###############################
installomatorInstall(){
    appToInstall=$1
    logging "Installing $appToInstall"
    /usr/local/Installomator/Installomator.sh "$appToInstall"
}

############################################### SwiftDialog (vervanger DEPNotify) ################
configDialog(){
    log_message="$instance: Installomator 1st with SwiftDialog, v$scriptVersion"
    printlog "[LOG-BEGIN] ${log_message}"

    # Internet check (1.1.1.1:53)
    if [[ "$(nc -z -v -G 10 1.1.1.1 53 2>&1 | grep -io "succeeded")" != "succeeded" ]]; then
        printlog "ERROR. No internet connection, we cannot continue."
        exit 90
    fi

    # Caffeinate
    /usr/bin/caffeinate -d -i -m -u &
    caffeinatepid=$!
    printlog "Total installations: $countLabels"

    # Logo (fallback: App Store)
    LOGO_PATH="/Library/Intune/Microsoft Intune Agent.app/Contents/Resources/AppIcon.icns"
    if [[ ! -a "${LOGO_PATH}" ]]; then
        if [[ $(/usr/bin/sw_vers -buildVersion) > "19" ]]; then
            LOGO_PATH="/System/Applications/App Store.app/Contents/Resources/AppIcon.icns"
        else
            LOGO_PATH="/Applications/App Store.app/Contents/Resources/AppIcon.icns"
        fi
    fi
    printlog "LOGO_PATH: $LOGO_PATH"

    # Maak leeg commandfile
    : > "$DIALOG_CMD_FILE" || true
}

startDialog() {
    currentUser="$(stat -f "%Su" /dev/console)"
    currentUserID=$(id -u "$currentUser")

    # Fallback indien binary niet in vaste pad
    if [[ ! -x "$DIALOG_BIN" ]]; then
        DIALOG_BIN="$(command -v dialog)"
    fi

    # Let op: elke regel met '\' moet eindigen op '\'
    # Commentaar op een aparte regel zetten!
    launchctl asuser "$currentUserID" "$DIALOG_BIN" \
        --title "$title" \
        --message "$message" \
        --icon "$LOGO_PATH" \
        --progress \
        --infotext "Logs: $logFolder" \
        --button1text "OK" \
        --button1disabled \
        --commandfile "$DIALOG_CMD_FILE" &
    
    sleep 1
    dialog_command "progress: 0"
    dialog_command "progresstext: Voorbereiden…"
}



dialog_command() {
    printlog "Dialog-command: $1"
    echo "$1" >> "$DIALOG_CMD_FILE"
}

runDialogInstallations(){
    if [[ -z "$LOGO_PATH" ]]; then
        echo "ERROR: LOGO_PATH empty. Exiting."
        exit 1
    fi

    local total=${#items[@]}
    local doneCount=0
    dialog_command "progress: 0"
    dialog_command "progresstext: Voorbereiden…"

    for item in "${items[@]}"; do
        itemName=$(/usr/local/Installomator/Installomator.sh "${item}" RETURN_LABEL_NAME=1 LOGGING=REQ INSTALL=force | tail -1)
        [[ "$itemName" == "#" || -z "$itemName" ]] && itemName="$item"

        dialog_command "progresstext: Installeren van ${itemName}…"
        printlog "Installing $item ($itemName)"

        cmdOutput="$( /usr/local/Installomator/Installomator.sh "${item}" ${installomatorOptions} || true )"
        exitStatus="$( echo "${cmdOutput}" | grep --binary-files=text -i "exit" | tail -1 | sed -E 's/.*exit code ([0-9]).*/\1/g' || true )"

        if [[ ${exitStatus} -eq 0 ]] ; then
            printlog "${item} succesfully installed."
            warnOutput="$( echo "${cmdOutput}" | grep --binary-files=text "WARN" || true )"
            [[ -n "$warnOutput" ]] && printlog "$warnOutput"
        else
            printlog "Error installing ${item}. Exit code ${exitStatus}"
            errorOutput="$( echo "${cmdOutput}" | grep --binary-files=text -i "error" || true )"
            [[ -n "$errorOutput" ]] && printlog "$errorOutput"
            ((errorCount++))
            errorLabels="$errorLabels ${item}"
        fi

        ((doneCount++))
        local pct=$(( (doneCount * 100) / total ))
        dialog_command "progress: $pct"
    done
}

endDialog(){
    # zet progress visueel op 100% en tekst op 'Klaar'
    dialog_command "progress: 100"
    dialog_command "progresstext: Klaar"
    dialog_command "button1: enable"          # <- OK wordt blauw/klikbaar

    printlog "Errors: $errorCount"
    if [[ $errorCount -ne 0 ]]; then
        finalMsg="${errorMessage} Total errors: $errorCount"
        dialog_command "title: Installatie met waarschuwingen"
        dialog_command "message: $finalMsg"
        dialog_command "button1text: OK"
    else
        dialog_command "title: Klaar"
        dialog_command "message: $endMessage"
        dialog_command "button1text: OK"
    fi
    printlog "Ending"
}


############################################### Privileges helper ###############################
install-privileges-helper(){
    helperPath="/Applications/Privileges.app/Contents/XPCServices/PrivilegesXPC.xpc/Contents/Library/LaunchServices/corp.sap.privileges.helper"
    if [[ -f "$helperPath" ]]; then
        [[ -d "/Library/PrivilegedHelperTools" ]] || { mkdir -p "/Library/PrivilegedHelperTools"; chmod 755 "/Library/PrivilegedHelperTools"; chown -R root:wheel "/Library/PrivilegedHelperTools"; }
        cp -f "$helperPath" "/Library/PrivilegedHelperTools"
        if [[ $? -eq 0 ]]; then
            chmod 755 "/Library/PrivilegedHelperTools/corp.sap.privileges.helper"
            helperPlistPath="/Library/LaunchDaemons/corp.sap.privileges.helper.plist"
            cat > "$helperPlistPath" << 'EOF'
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
            chmod 644 "$helperPlistPath"
            launchctl bootstrap system "$helperPlistPath" 2>/dev/null
            echo "/Applications/Privileges.app/Contents/Resources" > "/private/etc/paths.d/PrivilegesCLI"
        fi
    fi
}

############################################### Installomator bootstrap ##########################
downloadAndInstallInstallomator() {
    name="Installomator"
    printlog "$name check for installation"
    gitusername="Installomator"
    gitreponame="Installomator"
    filetype="pkg"
    downloadURL=$(curl -sfL "https://api.github.com/repos/$gitusername/$gitreponame/releases/latest" | awk -F '"' "/browser_download_url/ && /$filetype\"/ { print \$4; exit }")
    if [[ -z "$downloadURL" ]]; then
        downloadURL="https://github.com$(curl -sfL "$(curl -sfL "https://github.com/$gitusername/$gitreponame/releases/latest" | tr '\"' '\n' | grep -i 'expanded_assets' | head -1)" | tr '\"' '\n' | grep -i "^/.*\/releases\/download\/.*\.$filetype" | head -1)"
    fi
    appNewVersion=$(curl -sLI "https://github.com/$gitusername/$gitreponame/releases/latest" | grep -i "^location" | tr "/" "\n" | tail -1 | sed 's/[^0-9\.]//g')
    expectedTeamID="JME5BW3F3R"

    destFile="/usr/local/Installomator/Installomator.sh"
    currentInstalledVersion="$(${destFile} version 2>/dev/null || true)"
    printlog "${destFile} version: $currentInstalledVersion"

    if [[ ! -e "${destFile}" || "$currentInstalledVersion" != "$appNewVersion" ]]; then
        printlog "$name not found or not latest. Installing $appNewVersion"
        tmpDir="$(mktemp -d || true)"
        printlog "Working dir: $tmpDir"
        installationCount=0
        exitCode=9
        while [[ $installationCount -lt 3 && $exitCode -gt 0 ]]; do
            curl -Ls "$downloadURL" -o "$tmpDir/$name.pkg"
            curlDownloadStatus=$?
            if [[ $curlDownloadStatus -ne 0 ]]; then
                printlog "Download error ($curlDownloadStatus)"
                exitCode=1
            else
                teamID=$(spctl -a -vv -t install "$tmpDir/$name.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()' || true)
                printlog "Team ID: $teamID"
                if [[ "$expectedTeamID" = "$teamID" ]] || [[ -z "$expectedTeamID" ]]; then
                    pkgInstall=$(installer -verbose -dumplog -pkg "$tmpDir/$name.pkg" -target "/" 2>&1)
                    pkgInstallStatus=$?
                    if [[ $pkgInstallStatus -ne 0 ]]; then
                        printlog "Install error: $pkgInstall"
                        exitCode=2
                    else
                        printlog "$name installed."
                        exitCode=0
                    fi
                else
                    printlog "Team ID mismatch."
                    exitCode=3
                fi
            fi
            ((installationCount++))
            if [[ $installationCount -lt 3 && $exitCode -gt 0 ]]; then
                printlog "Retrying... ($installationCount)"
                rm -f "$tmpDir/$name.pkg"
                sleep 2
            fi
        done
        printlog "Remove $(rm -Rfv "${tmpDir}" || true)"
        if [[ $exitCode != 0 ]]; then
            printlog "ERROR. Installation of $name failed. Aborting."
            caffexit $exitCode
        fi
    else
        printlog "$name version $appNewVersion already installed."
    fi
}

############################################### Housekeeping #####################################
caffexit () {
    kill "$caffeinatepid" 2>/dev/null || true
    printlog "[LOG-END] Status $1"
    exit $1
}

############################################### Start ############################################
main
