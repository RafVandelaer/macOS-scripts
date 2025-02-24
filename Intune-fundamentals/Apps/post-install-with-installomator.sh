#!/bin/bash

# Define the application to install
appToInstall="bbedit"

# Define the log file path
logFile="/var/log/${appToInstall}.log"

# Check if Installomator is installed
installomatorPath="/usr/local/Installomator/Installomator.sh"
if [ ! -f "$installomatorPath" ]; then
    echo "Installomator is not installed. Please install it before running this script."
    exit 1
fi

# Create the log file if it doesn't exist
[[ -f "$logFile" ]] || touch "$logFile"

# Install the application and log the output
"$installomatorPath" "$appToInstall" >> "$logFile"

# Exit the script
exit 0
