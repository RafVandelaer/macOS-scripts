#!/bin/bash

LOG="/var/log/intune-printer-queue.log"
PLIST="/var/tmp/printer-authz.plist"
GROUP="staff"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG"
}

log "🔧 Starting printer authorization policy update..."

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
  log "Script must be run as root. Exiting."
  exit 1
fi

# Create temporary authorization plist
defaults write "${PLIST}" allow-root -bool TRUE
defaults write "${PLIST}" authenticate-user -bool TRUE
defaults write "${PLIST}" class -string user
defaults write "${PLIST}" group "${GROUP}"
defaults write "${PLIST}" session-owner -bool TRUE
defaults write "${PLIST}" shared -bool TRUE
log "Created authorization policy plist for group '$GROUP'"

# List of authorization domains to update
preferences=(
  "system.preferences"
  "system.preferences.printing"
  "system.print.admin"
)

# Apply the custom policy to each domain
for preference in "${preferences[@]}"; do
  /usr/bin/security authorizationdb write "${preference}" < "${PLIST}" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    log "Successfully updated policy: $preference"
  else
    log "Failed to update policy: $preference"
  fi
done

# Clean up temporary plist
rm -f "$PLIST"
log "🧹 Temporary plist removed"

log "Printer authorization policy update completed"
exit 0