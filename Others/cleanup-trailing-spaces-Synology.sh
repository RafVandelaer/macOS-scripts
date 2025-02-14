#!/bin/sh
# Usage: ./cleanup_trailing_spaces.sh [-d|--dry-run] [directory]
#
# Description:
# This script recursively finds all files and directories that end with a space
# and renames them to remove the trailing space. Optimized for Synology NAS.
# If no directory is specified, it searches through the current directory.
# Use the dry-run option to preview what would be renamed without making changes.
#
# Options:
# -d, --dry-run Show what would be renamed without actually renaming anything
#
# Arguments:
# directory Optional: Directory to search in (default: current directory)
#
# Examples:
# ./cleanup_trailing_spaces.sh # Process current directory
# ./cleanup_trailing_spaces.sh -d # Dry run in current directory
# ./cleanup_trailing_spaces.sh /path/to/dir # Process specific directory
# ./cleanup_trailing_spaces.sh -d /path/to/dir # Dry run in specific directory

# Function to print usage
print_usage() {
    sed -n '/^#/p' "$0" | grep -v '#!/bin/sh' | sed 's/^#//'
    exit 1
}

# Process command line arguments
DRY_RUN=0
SEARCH_DIR="."

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            print_usage
            ;;
        *)
            if [ -d "$1" ]; then
                SEARCH_DIR="$1"
            else
                echo "Error: Directory '$1' does not exist or is not a directory"
                print_usage
            fi
            shift
            ;;
    esac
done

# Convert search directory to absolute path
SEARCH_DIR=$(cd "$SEARCH_DIR" && pwd) || {
    echo "Error: Unable to access directory '$SEARCH_DIR'"
    exit 1
}

# Function to handle the renaming of files and directories
handle_item() {
    item="$1"
    type="$2"
    newname="${item% }" # Remove trailing space
    
    [ "$item" = "$newname" ] && return # Skip if no trailing space
    
    if [ $DRY_RUN -eq 1 ]; then
        echo "[DRY RUN] Would rename ${type}:"
        echo " From: '$item'"
        echo " To: '$newname'"
    else
        if [ -e "$item" ]; then # Check if item still exists
            if mv "$item" "$newname"; then
                echo "Renamed ${type}:"
                echo " From: '$item'"
                echo " To: '$newname'"
            else
                echo "Failed to rename ${type}: '$item'"
            fi
        fi
    fi
}

echo "Recursively searching for items ending with a space in: $SEARCH_DIR"

# Process items in reverse order (deepest first)
# Using find with -exec to handle spaces in filenames more reliably
find "$SEARCH_DIR" -depth -name "* " -type d -exec sh -c '
    for item do
        handle_item "$item" "directory"
    done
' sh {} +

find "$SEARCH_DIR" -depth -name "* " -type f -exec sh -c '
    for item do
        handle_item "$item" "file"
    done
' sh {} +

# Print summary
if [ $DRY_RUN -eq 1 ]; then
    echo "Dry run completed. No files or directories were actually renamed in: $SEARCH_DIR"
else
    echo "Recursive rename completed in: $SEARCH_DIR"
fi
