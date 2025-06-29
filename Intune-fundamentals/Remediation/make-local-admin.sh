#!/bin/zsh

#creating an admin user AFTER enrollment. The script waits for the dock to be available. 
until ps aux | grep /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock | grep -v grep &>/dev/null; do
		delay=$(( $RANDOM % 50 + 10 ))
		echo "$(date) |  + Dock not running, waiting [$delay] seconds"
		sleep $delay
done
sysadminctl -addUser it -fullName "" -password "" -admin
exit 0