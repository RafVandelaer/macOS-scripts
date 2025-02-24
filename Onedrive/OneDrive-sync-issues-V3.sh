#!/bin/bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# Get the user
loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' );
loggedinuser="$(scutil <<<"show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')"

#in de functie main worden alle mogelijke files gecheckt. Als we deze opdelen door eerst een search functie te maken om dan elke soort aan te pakken na 
# Ok van user


#Backup aanmaken van volledige OneDrive bij aanpassen fouten? 
createBackup=false;

#Create log
fixdate="$(date +%d%m%Y-%H-%M)"

[[ -d "/var/log/onedrive-fixlogs" ]] || mkdir "/var/log/onedrive-fixlogs"

fixlog="/var/log/onedrive-fixlogs/onedrive-fixlog-""$fixdate"
readonly fixlog

logging () {
	echo "$fixdate"": " $1 | tee -a "$fixlog";
}

#check if swiftDialog is installed

if [ ! -f "$DIALOG_PATH" ]; then
    logging "SwiftDialog not found. Installing using Installomator..."
    /usr/local/Installomator/Installomator.sh swiftdialog
else
    logging "SwiftDialog is already installed."
fi


onedrivefolder=$HOME/Library/CloudStorage/$(ls ~/Library/CloudStorage/ | grep -Ei "onedrive" | grep -Evi "personal|persoonlijk|library|bibliotheken" | head -n 1)



########################################################################################################
#
# Modified by Raf Vandelaer to make it automatically check OneDrive an prompt to edit these errors.
#
# February 22, 2025
# Added swift dialog functionality to make messages more clear.
#
#
#
# Modified (find) to mdfind commando to make the script faster
#
#
# Jamf  Script to check user's OneDrive folder for illegal
# characters, leading or trailing spaces and corrects them to 
# allow smooth synchronization.
#
# Modified by soundsnw, January 26, 2020
#
# Important: The OneDrive folder name used in your organization 
# needs to be specified in the script (line 171)
#
# If you want a slightly faster script, at the cost of not making a backup,
# comment out or delete line 221-228 and edit the Jamf notifications at the end.
#
# Changelog
# March 25, 2024
# - Modified (find) to mdfind commando to make the script faster
# - Modified logging to a central function
# - Removed backup function for fast working.
#	
# January 26, 2020
# - Fixed numerical conditionals in while loops and file number comparisons, corrected quoting.
#
# September 8, 2019
# - Treats directories first
# - If the corrected filename is used by another file, appends a number at the end to 
#   avoid overwriting
# - Checks if the number of files before and after renaming is the same
# - Uses mktemp for temp files
# - Restarts OneDrive and cleans up temp files if aborted
# - Uses local and readonly variables where appropriate
#
# September 4, 2019
# - Changed backup parent directory to user folder to avoid potential problems
#   if Desktop sync is turned on
#
# September 3, 2019
# - The script is now much faster, while still logging and making a backup before changing filenames
# - Backup being made using APFS clonefile (support for HFS dropped)
# - Spotlight prevented from indexing backup to prevent users from opening the wrong file later
#
# September 2, 2019
# - Only does rename operations on relevant files, for increased speed and safety
# - No longer fixes # or %, which are supported in more recent versions of OneDrive
#   https://support.office.com/en-us/article/invalid-file-names-and-file-types-in-onedrive-onedrive-for-business-and-sharepoint-64883a5d-228e-48f5-b3d2-eb39e07630fa#invalidcharacters
# - Changed all exit status codes to 0, to keep things looking tidy in Self Service
# - No longer removes .fstemp files before doing rename operations
#
# Version: 0.6
#
# Original script by dsavage:
# https://github.com/UoE-macOS/jss/blob/master/utilities-fix-file-names.sh
#
# Use of this script is entirely at your own risk, there is no warranty.
#
########################################################################################################

set -o pipefail

unset fixchars fixtrail fixlead


# Cleanup function, removes temp files and restarts OneDrive

function finish() {

	[[ -z "$fixchars" ]] || rm -f "$fixchars"
	[[ -z "$fixtrail" ]] || rm -f "$fixtrail"
	[[ -z "$fixlead" ]] || rm -f "$fixlead"

	logging "Starting Onedrive..."
	[[ $(pgrep "OneDrive\b") ]] || open -gj "/Applications/OneDrive.app"

	[[ ! $(pgrep "caffeinate") ]] || killall "caffeinate"
	rm /tmp/odfailures

	exit 0

}
trap finish HUP INT QUIT TERM

# Make sure the machine does not sleep until the script is finished

(caffeinate -sim -t 3600) &
disown

# Filename correction functions

fix_trailing_chars() {

	local linecount counter line name path fixedname
	linecount="$(wc -l "$fixtrail" | awk '{print $1}')"
	counter="$linecount"

	while ! [ "$counter" -eq 0 ]; do

		line="$(sed -n "${counter}"p "$fixtrail")"
		name="$(basename "$line")"
		path="$(dirname "$line")"
		fixedname="$(echo "$name" | awk '{sub(/[ \t]+$/, "")};1')"

		if [[ -f "$path"'/'"$fixedname" ]] || [[ -d "$path"'/'"$fixedname" ]]; then

			mv -vf "$line" "$path"'/'"$fixedname"'-'"$(jot -nr 1 100000 999999)" >>"$fixlog"

		else

			mv -vf "$line" "$path"'/'"$fixedname" >>"$fixlog"

		fi

		((counter = counter - 1))
	done
}

fix_leading_spaces() {

	local linecount counter line name path fixedname
	linecount="$(wc -l "$fixlead" | awk '{print $1}')"
	counter="$linecount"
	while ! [ "$counter" -eq 0 ]; do

		line="$(sed -n "${counter}"p "$fixlead")"
		name="$(basename "$line")"
		path="$(dirname "$line")"
		fixedname="$(echo "$name" | sed -e 's/^[ \t]//')"

		if [[ -f "$path"'/'"$fixedname" ]] || [[ -d "$path"'/'"$fixedname" ]]; then

			mv -vf "$line" "$path"'/'"$fixedname"'-'"$(jot -nr 1 100000 999999)" >>"$fixlog"
		else

			mv -vf "$line" "$path"'/'"$fixedname" >>"$fixlog"

		fi

		((counter = counter - 1))
	done
}
fix_names() {

	local linecount counter line name path fixedname
	linecount="$(wc -l "$fixchars" | awk '{print $1}')"
	counter="$linecount"
	while ! [ "$counter" -eq 0 ]; do

		line="$(sed -n "${counter}"p "$fixchars")"
		name="$(basename "$line")"
		path="$(dirname "$line")"
		fixedname="$(echo "$name" | tr ':' '-' | tr '\\' '-' | tr '?' '-' | tr '*' '-' | tr '"' '-' | tr '<' '-' | tr '>' '-' | tr '|' '-')"

		if [[ -f "$path"'/'"$fixedname" ]] || [[ -d "$path"'/'"$fixedname" ]]; then

			mv -vf "$line" "$path"'/'"$fixedname"'-'"$(jot -nr 1 100000 999999)" >>"$fixlog"

		else

			mv -vf "$line" "$path"'/'"$fixedname" >>"$fixlog"

		fi

		((counter = counter - 1))
	done
}

function main() {


	# Check if file system is APFS
	if(($createBackup)); then
		local apfscheck
		apfscheck="$(diskutil info / | awk '/Type \(Bundle\)/ {print $3}')"

		if [[ "$apfscheck" == "apfs" ]]; then

			logging "File system is APFS, the script may continue."

		else

			logging "File system not supported, aborting."

			/usr/local/jamf/bin/jamf displayMessage -message "Het filesysteem van deze mac is niet supported, upgrade naar macOS High Sierra of hoger."

			exit 0

		fi
	fi

	# Check if OneDrive folder is present
	# Make backup using APFS clonefile, prevent the backup from being indexed by Spotlight

	if [ -d "$onedrivefolder" ]; then

		logging "OneDrive directory is present. Stopping OneDrive."

		killall OneDrive || true
		if(($createBackup)); then
			beforefix_size=$(du -sk "$onedrivefolder" | awk -F '\t' '{print $1}')
			readonly beforefix_size
			beforefix_filecount=$(find "$onedrivefolder" | wc -l | sed -e 's/^ *//')
			readonly beforefix_filecount
	
			echo "$(date +%m%d%y-%H%M)"": The OneDrive folder is using ""$beforefix_size"" KB and the file count is ""$beforefix_filecount"" before fixing filenames." | tee -a "$fixlog"
	
			
			rm -drf "/Users/""$loggedinuser""/FF-Backup-*"
			mkdir -p "/Users/""$loggedinuser""/FF-Backup-""$fixdate""/""$fixdate"".noindex"
			chown "$loggedinuser":staff "/Users/""$loggedinuser""/FF-Backup-""$fixdate"
			chown "$loggedinuser":staff "/Users/""$loggedinuser""/FF-Backup-""$fixdate""/""$fixdate"".noindex"
			touch "/Users/""$loggedinuser""/FF-Backup-""$fixdate""/""$fixdate"".noindex/.metadata_never_index"
			cp -cpR "$onedrivefolder" "/Users/""$loggedinuser""/FF-Backup-""$fixdate""/""$fixdate"".noindex"
			
			text = "APFS clonefile backup created at /Users/""$loggedinuser""/FF-Backup-""$fixdate""/""$fixdate"".noindex."
			logging $text
		fi
	else

		logging "OneDrive directory not present, aborting."

		/usr/local/jamf/bin/jamf displayMessage -message "Kan de OneDrive folder niet vinden. Vraag aan IT om dit aan te passen."
		exit 0

	fi

	# Fix directory filenames

	logging "Fixing illegal characters in directory names"
	fixchars="$(mktemp)"
	readonly fixchars
	mdfind -onlyin "$onedrivefolder" 'kMDItemFSName == "*[\\:*?\"<>|]*"c && kMDItemContentType == "public.folder"' > "$fixchars"
	#find "${onedrivefolder}" -type d -name '*[\\:*?"<>|]*' -print >"$fixchars"
	fix_names

	logging "Fixing trailing characters in directory names"
	fixtrail="$(mktemp)"
	readonly fixtrail

	# Use mdfind to locate directories with names ending in a space
	mdfind -onlyin "$onedrivefolder" 'kMDItemFSName == "* "c && kMDItemContentType == "public.folder"' > "$fixtrail"
	# Use mdfind to locate directories with names ending in a period and append to the log
	mdfind -onlyin "$onedrivefolder" 'kMDItemFSName == "*."c && kMDItemContentType == "public.folder"' >> "$fixtrail"
	#find "${onedrivefolder}" -type d -name "* " -print >"$fixtrail"
	#find "${onedrivefolder}" -type d -name "*." -print >>"$fixtrail"
	fix_trailing_chars

	 logging "Fixing leading spaces in directory names"
	fixlead="$(mktemp)"
	readonly fixlead
	find "${onedrivefolder}" -type d -name " *" -print >"$fixlead"
	fix_leading_spaces

	# Fix all other filenames

	logging "Fixing illegal characters in filenames"

	find "${onedrivefolder}" -name '*[\\:*?"<>|]*' -print >"$fixchars"
	fix_names

	logging "Fixing trailing characters in filenames"
	find "${onedrivefolder}" -name "* " -print >"$fixtrail"
	find "${onedrivefolder}" -name "*." -print >>"$fixtrail"
	fix_trailing_chars

	logging "Fixing leading spaces in filenames"
	find "${onedrivefolder}" -name " *" -print >"$fixlead"
	fix_leading_spaces

	# Check OneDrive directory size and filecount after applying name fixes
	if(($createBackup)); then
		afterfix_size=$(du -sk "$onedrivefolder" | awk -F '\t' '{print $1}')
		readonly afterfix_size
		afterfix_filecount=$(find "$onedrivefolder" | wc -l | sed -e 's/^ *//')
		readonly afterfix_filecount
	
		$text = "The OneDrive folder is using ""$afterfix_size"" KB and the file count is ""$afterfix_filecount"" after fixing filenames. Restarting OneDrive." 
		logging $text
	
		if [[ "$beforefix_filecount" -eq "$afterfix_filecount" ]]; then
			if(($createBackup)); then
				/usr/local/jamf/bin/jamf displayMessage -message "De bestandsnamen zijn correct aangepast. Er is een backup van de originele bestanden gemaakt in de map FF-Backup-$fixdate in jouw user map. De backup wordt automatisch verwijdert bij de volgende hernoeming van bestanden."
			fi
		else
	
			logging "Check filenames"
			#/usr/local/jamf/bin/jamf displayMessage -message "Er liep iets fout. Er werd voor de zekerheid een backup in FF-Backup-$fixdate geplaatst."
	
		fi
	fi

}

loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' );


if [[ -d "$onedrivefolder" ]] ; then

	#find "${onedrivefolder}" -name '*[\\:*?"<>|]*' -print > /tmp/odfailures
	#find "${onedrivefolder}" -name "* " -print >> /tmp/odfailures
	#find "${onedrivefolder}" -name "*." -print >> /tmp/odfailures
	#find "${onedrivefolder}" -name " *" -print >> /tmp/odfailures
	
	
	mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '*?*"  > /tmp/odfailures
	mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '*|*" >> /tmp/odfailures
	mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '* " >> /tmp/odfailures
	mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '*." >> /tmp/odfailures
	mdfind -onlyin "$onedrivefolder" "kMDItemFSName == ' *" >> /tmp/odfailures
	mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '\\" >> /tmp/odfailures
	mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '*>*" >> /tmp/odfailures
	mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '*<*" >> /tmp/odfailures
	mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '*:*" >> /tmp/odfailures
	
	# -print >> /tmp/odfailures
	
	odsyncfailures=$(cat /tmp/odfailures | wc -l | sed -e 's/^ *//')
	
	#echo $odsyncfailures
	
	
	# Define the AppleScript code for displaying the popup with buttons
	
	if(($odsyncfailures)); then
		popup_result=$(osascript -e 'tell app "System Events" to display dialog "Er zijn fouten gevonden in OneDrive. Hierdoor kunnen er geen bestanden gesynchroniseert worden.\nWil je deze fouten oplossen?" with icon caution')
				
		# Check the button clicked by the user
		if [[ "$popup_result" == *"OK"* ]]; then
			logging "User requested to solve issues. Solving..."
			main
			finish
		elif [[ "$popup_result" == *"Cancel"* ]]; then
			logging "User requested to NOT to solve issues. Aborting..."
			sudo rm /tmp/odfailures
		elif [[ "$popup_result" == *"Annuleer"* ]]; then
			logging "User requested to NOT to solve issues. Aborting..."
			sudo rm /tmp/odfailures
		else
			logging "User requested to NOT to solve issues. Aborting..."
			#popup_result=$(osascript -e 'tell app "System Events" to display message "Let op: de fouten blijven staan, je zal dit handmatig moeten oplossen." buttons {"OK"} ')
			/usr/local/jamf/bin/jamf displayMessage -message "Let op: controleer de fouten binnen OneDrive, dit voorkomt dat je synchronisatie niet werkt."
			sudo rm /tmp/odfailures
		fi
	else
		logging "No errors found in this OneDrive."
	fi	
	
	
	
	
	

else

echo "Geen fouten gevonden."

fi






