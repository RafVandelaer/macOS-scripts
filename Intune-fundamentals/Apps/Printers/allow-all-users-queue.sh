#!/bin/bash

LOGFILE="/var/log/printer-rights.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

run_cmd() {
    CMD=$1
    DESC=$2

    eval "$CMD"
    if [[ $? -eq 0 ]]; then
        log "SUCCESS: $DESC"
    else
        log "ERROR: $DESC (cmd: $CMD)"
    fi
}

log "🔧 Starting printer permissions configuration..."

# Allow access to "Printers & Scanners" system preference without authentication
run_cmd "/usr/bin/security authorizationdb write system.preferences.printing allow" \
        "Allow users to access 'Printers & Scanners' system preference without authentication"

# Allow print operator actions (pause/resume/clear print jobs) without authentication
run_cmd "/usr/bin/security authorizationdb write system.print.operator allow" \
        "Allow users to perform print operator actions without authentication"

# Add 'everyone' group to lpadmin
run_cmd "/usr/sbin/dseditgroup -o edit -n /Local/Default -a everyone -t group lpadmin" \
        "Add 'everyone' to the 'lpadmin' group"

# Add 'everyone' group to _lpadmin
run_cmd "/usr/sbin/dseditgroup -o edit -n /Local/Default -a everyone -t group _lpadmin" \
        "Add 'everyone' to the '_lpadmin' group"

log "Completed: Printer permissions have been configured."
exit 0
