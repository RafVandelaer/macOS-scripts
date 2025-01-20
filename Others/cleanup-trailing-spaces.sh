#!/bin/bash

# Usage: ./cleanup_trailing_spaces.sh [-d|--dry-run] [directory]
#
# Description:
#   This script recursively finds all files and directories that end with a space
#   and renames them to remove the trailing space.
#   If no directory is specified, it searches through the current directory.
#   Use the dry-run option to preview what would be renamed without making changes.
#
# Options:
#   -d, --dry-run    Show what would be renamed without actually renaming anything
#
# Arguments:
#   directory        Optional: Directory to search in (default: current directory)
#
# Examples:
#   ./cleanup_trailing_spaces.sh         # Process current directory
#   ./cleanup_trailing_spaces.sh -d      # Dry run in current directory
#   ./cleanup_trailing_spaces.sh /path/to/dir    # Process specific directory
#   ./cleanup_trailing_spaces.sh -d /path/to/dir # Dry run in specific directory

# Function to print usage
print_usage() {
    grep '^#' "$0" | grep -v '#!/bin/bash' | sed 's/^#//'
    exit 1
}

# Process command line arguments
DRY_RUN=0
SEARCH_DIR="."

while [[ $# -gt 0 ]]; do
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
    local item="$1"
    local type="$2"
    local newname="${item% }"  # Remove trailing space
    
    if [ "$item" = "$newname" ]; then
        return  # Skip if no trailing space
    fi
    
    if [ $DRY_RUN -eq 1 ]; then
        echo "[DRY RUN] Would rename ${type}:"
        echo "  From: '$item'"
        echo "  To:   '$newname'"
    else
        if [ -e "$item" ]; then  # Check if item still exists
            mv "$item" "$newname" && echo "Renamed ${type}:" && \
            echo "  From: '$item'" && \
            echo "  To:   '$newname'" || \
            echo "Failed to rename ${type}: '$item'"
        fi
    fi
}

echo "Recursively searching for items ending with a space in: $SEARCH_DIR"

# Use find with -print0 and process with while read -d $'\0' for proper handling of spaces
# Process items in reverse order (deepest first) for proper handling of nested items
find "$SEARCH_DIR" -name "* " -print0 2>/dev/null | sort -rz | while IFS= read -r -d $'\0' item; do
    if [ -d "$item" ]; then
        handle_item "$item" "directory"
    elif [ -f "$item" ]; then
        handle_item "$item" "file"
    fi
done

# Print summary
if [ $DRY_RUN -eq 1 ]; then
    echo "Dry run completed. No files or directories were actually renamed in: $SEARCH_DIR"
else
    echo "Recursive rename completed in: $SEARCH_DIR"
fi
