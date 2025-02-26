#!/bin/bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

########################################################################################################
#
# Modified by Raf Vandelaer to make it automatically check OneDrive an prompt to edit these errors.
#
# February 22, 2025
# Added swift dialog functionality to make messages more clear.
# changed script for better speed, lesser code.
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



# Get the user
loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }' );
DIALOG="/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog"

errorlist="/tmp/onedriveErrors.log"
truncate -s 0 "$errorlist"  # Clears the file


#Create log
fixdate="$(date +%d%m%Y-%H-%M)"

[[ -d "/var/log/onedrive-fixlogs" ]] || mkdir "/var/log/onedrive-fixlogs"

fixlog="/var/log/onedrive-fixlogs/onedrive-fixlog-""$fixdate"".log"
readonly fixlog

logging () {
	echo "$fixdate"": " $1 | tee -a "$fixlog";
}

#check if swiftDialog is installed

if [ ! -f "$DIALOG" ]; then
    logging "SwiftDialog not found. Installing using Installomator..."
    /usr/local/Installomator/Installomator.sh swiftdialog
else
    logging "SwiftDialog is already installed."
fi


onedrivefolder=$HOME/Library/CloudStorage/$(ls ~/Library/CloudStorage/ | grep -Ei "onedrive" | grep -Evi "personal|persoonlijk|library|bibliotheken" | head -n 1)




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
	#rm $errorlist
    logging "All done!" 

	exit 0

}
trap finish HUP INT QUIT TERM

# Make sure the machine does not sleep until the script is finished

(caffeinate -sim -t 3600) &
disown


function start (){
    	if [ -d "$onedrivefolder" ]; then

		logging "OneDrive directory $onedrivefolder is present. Stopping OneDrive."
		killall OneDrive || true

        getErrors
		if [[ ! -s "$errorlist" ]]; then
			logging "no errors found, finishing up."
			echo "File is empty"
		else
			setDialog
		fi
       

        finish

		
	    else

		logging "OneDrive directory not present, aborting."

        #TODO
		/usr/local/jamf/bin/jamf displayMessage -message "Kan de OneDrive folder niet vinden. Gelieve OneDrive te configureren."
		exit 0

	    fi
}
function setDialog(){
    # Define the full path to SwiftDialog
    DIALOG="/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog"

    # Read the contents of the errorlist file into a variable and remove duplicates
    errors=$(awk '!seen[$0]++' "$errorlist")

    # Set Internal Field Separator to newline to handle filenames with spaces correctly
    IFS=$'\n'

    # Initialize an array to store the filenames
    LIST_ITEMS=()

    # Loop through each line in the errorlist and extract the filename
    for path in $errors; do
        filename=$(basename "$path")
        LIST_ITEMS+=("--listitem" "$filename")
    done

    # Reset IFS to default (optional)
    IFS=$' \t\n'

    # Define the STATUS_MESSAGE variable (replace with your actual status message)
    STATUS_MESSAGE="Volgende fouten werden in OneDrive gevonden. Druk op Oké om deze bestandsnamen aan te passen."

    # Run SwiftDialog with dynamic list and status message
    "$DIALOG" \
    --title "OneDrive fouten" \
    --message "$STATUS_MESSAGE" \
    --icon "/System/Applications/App Store.app/Contents/Resources/AppIcon.icns" \
    "${LIST_ITEMS[@]}" \
    --button1 "OK" \
    --button2 "Cancel" \
    --moveable

    # Capture the exit status of the SwiftDialog command
    DIALOG_EXIT_STATUS=$?

    # Print the exit status to debug
    echo "SwiftDialog exit status: $DIALOG_EXIT_STATUS"

    # Check the exit status to determine which button was pressed
    if [[ $DIALOG_EXIT_STATUS -eq 0 ]]; then
        logging "User pressed OK, fixing..."
        fix_leading_spaces
        fix_names
        fix_trailing_chars

    elif [[ $DIALOG_EXIT_STATUS -eq 2 ]]; then
        logging "User pressed Cancel. No fixing."

    else
        logging "No button pressed or dialog closed"
    fi
}


function getErrors(){
    logging "Finding illegal characters in directory names"

    logging "Finding trailing characters in directory names"
    fixchars=$(mktemp /tmp/XXXXXX)
	readonly fixchars
	fixtrail="$(mktemp)"
	readonly fixtrail
    fixlead="$(mktemp)"
	readonly fixlead

		mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '*?*'" | tee -a "$fixchars" >> "$errorlist"
		mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '*|*'" | tee -a "$fixchars" >> "$errorlist"
		mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '* '"  | tee -a "$fixtrail" >> "$errorlist"
		mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '*.'"  | tee -a "$fixchars" >> "$errorlist"
		mdfind -onlyin "$onedrivefolder" "kMDItemFSName == ' *'"  | tee -a "$fixlead"  >> "$errorlist"
		mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '\\'"  | tee -a "$fixchars" >> "$errorlist"
		mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '*>*'" | tee -a "$fixchars" >> "$errorlist"
		mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '*<*'" | tee -a "$fixchars" >> "$errorlist"
		mdfind -onlyin "$onedrivefolder" "kMDItemFSName == '*:*'" | tee -a "$fixchars" >> "$errorlist"


}
fix_trailing_chars() {

    logging "Fixing trailing chars..."

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
     logging "Fixing leading spaces..."


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


function fix_names(){

	local linecount counter line name path fixedname
	linecount="$(wc -l "$fixchars" | awk '{print $1}')"
	counter="$linecount"
	while ! [ "$counter" -eq 0 ]; do
		line="$(sed -n "${counter}"p "$fixchars")"
		name="$(basename "$line")"
		path="$(dirname "$line")"
		#fixedname="$(echo "$name" | tr ':' '-' | tr '\\' '-' | tr '?' '-' | tr '*' '-' | tr '"' '-' | tr '<' '-' | tr '>' '-' | tr '|' '-')"
		fixedname="$(echo "$name" | sed 's/[:?|\\"<>*]/-/g')"

		if [[ -f "$path"'/'"$fixedname" ]] || [[ -d "$path"'/'"$fixedname" ]]; then

			mv -vf "$line" "$path"'/'"$fixedname"'-'"$(jot -nr 1 100000 999999)" >>"$fixlog"

		else

			mv -vf "$line" "$path"'/'"$fixedname" >>"$fixlog"

		fi

		((counter = counter - 1))
	done
}

start
