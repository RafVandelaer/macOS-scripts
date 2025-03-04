#!/bin/bash

LOGFILE="$HOME/Desktop/fix_trailing_spaces.log"

# Default mode: dry-run
DRY_RUN=true
REPLACEMENT_STRING="-trailingSpace-"

SEARCH_METHOD="find"

# Function to print usage
print_usage() {
    sed -n '/^#/p' "$0" | grep -v '#!/bin/bash' | sed 's/^#//'
    exit 1
}

# This script scans an SMB or AFP directory and checks which directories have a trailing space.
# If a trailing space is found, it renames the directory by replacing the space with a custom string.
#
# By default, the script runs in dry-run mode, meaning it only shows what it would rename.
# Use the --apply option to actually rename directories.
#
# Usage:
#   ./fix_trailing_spaces.sh             # Runs in dry-run mode (default).
#   ./fix_trailing_spaces.sh --apply     # Applies the changes (renames directories).
#   ./fix_trailing_spaces.sh --help      # Shows this help message.

# Check for script arguments
for arg in "$@"; do
    case $arg in
        --apply)
            DRY_RUN=false
            ;;
        --help)
            print_usage
            ;;
        *)
            echo "Unknown option: $arg"
            print_usage
            ;;
    esac
done

if [ "$DRY_RUN" = false ]; then
        echo -e "\033[33mYou used the --apply argument, this will change the directories with trailing spaces. Consider using the script without --apply first.\033[0m"  # Yellow text
        sleep 2
fi

# Ask if the user wants to use Spotlight index (mdfind) or not
read -rp "Do you want to use Spotlight indexing (mdfind) for faster searching? [y/N]: " USE_SPOTLIGHT
USE_SPOTLIGHT=${USE_SPOTLIGHT:-N}  # Default to 'N' if the user doesn't provide input.

if [[ "$USE_SPOTLIGHT" =~ ^[Yy]$ ]]; then
    SEARCH_METHOD="mdfind"
fi

# Ask for target directory
read -rp "Enter the full path of the SMB/AFP directory to scan (mostly in /Volumes/... for SMB mounts): " TARGET_DIR

# Verify that the directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory does not exist: $TARGET_DIR"
    exit 1
fi

# Ask for custom replacement string
read -rp "Enter the replacement string for trailing spaces (default: '-trailingSpace-', press enter): " USER_INPUT
if [[ -n "$USER_INPUT" ]]; then
    REPLACEMENT_STRING="$USER_INPUT"
fi

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

# Function to process directories using the selected search method
process_directories() {
    log_message "Scanning directory: $TARGET_DIR"
    log_message "Replacement string: '$REPLACEMENT_STRING'"
    
    if [ "$SEARCH_METHOD" = "mdfind" ]; then
        # Use mdfind for Spotlight search
        mdfind "kMDItemFSName=* " -onlyin "$TARGET_DIR" | while read -r dir; do
            new_dir="${dir% }$REPLACEMENT_STRING"

            if $DRY_RUN; then
                log_message "[Dry Run] Would rename: '$dir' -> '$new_dir'"
            else
                echo "Renaming: '$dir' -> '$new_dir'"
                mv "$dir" "$new_dir"
                log_message "Renamed: '$dir' -> '$new_dir'"
            fi
        done
    else
        find "$TARGET_DIR" -type d -name "* " -print0 | while IFS= read -r -d '' dir; do
            new_dir="${dir% }$REPLACEMENT_STRING"

            if $DRY_RUN; then
                log_message "[Dry Run] Would rename: '$dir' -> '$new_dir'"
            else
                echo "Renaming: '$dir' -> '$new_dir'"
                mv "$dir" "$new_dir"
                log_message "Renamed: '$dir' -> '$new_dir'"
            fi
        done
    fi

    log_message "Scan completed."
}


process_directories
