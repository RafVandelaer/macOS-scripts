#!/bin/bash

# Usage: ./cleanup_trailing_spaces.sh [-d|--dry-run] [directory]
#
# Description:
#   Removes trailing spaces from files/directories, compatible with AFP mounts
#   Handles local and network storage (including Synology NAS via AFP)
#
# Options:
#   -d, --dry-run    Preview changes without renaming
#   directory        Optional: Directory to process (default: current)

DRY_RUN=0
SEARCH_DIR="."


while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run) DRY_RUN=1; shift ;;
        -h|--help) grep '^#' "$0" | grep -v '#!/bin/bash' | sed 's/^#//'; exit 1 ;;
        *) [[ -d "$1" ]] && SEARCH_DIR="$1" || { echo "Error: Invalid directory '$1'"; exit 1; }; shift ;;
    esac
done

SEARCH_DIR=$(cd "$SEARCH_DIR" && pwd) || { echo "Error: Cannot access '$SEARCH_DIR'"; exit 1; }

handle_item() {
    local item="$1"
    local type="$2"
    local newname="${item% }"
    
    [[ "$item" = "$newname" ]] && return
    
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[DRY RUN] Would rename ${type}:"
        echo "  From: '$item'"
        echo "  To:   '$newname'"
        return
    fi
    
    if [[ -e "$item" ]]; then
        mv "$item" "$newname" && {
            echo "Renamed ${type}:"
            echo "  From: '$item'"
            echo "  To:   '$newname'"
            touch "$newname" 2>/dev/null
        } || echo "Failed to rename ${type}: '$item'"
    fi
}

echo "Searching in: $SEARCH_DIR"

find "$SEARCH_DIR" -type d -exec sh -c '
    for d; do
        cd "$d" 2>/dev/null || continue
        ls -1A | grep " $" | while IFS= read -r f; do
            echo "$d/$f"
        done
    done
' sh {} + | sort -r | while IFS= read -r item; do
    [[ -d "$item" ]] && handle_item "$item" "directory"
    [[ -f "$item" ]] && handle_item "$item" "file"
done

echo "${DRY_RUN:+[DRY RUN] }Processing completed in: $SEARCH_DIR"