#!/bin/bash

# Define the full path to SwiftDialog
DIALOG="/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog"

# Initialize an empty array to hold invalid items
LIST_ITEMS=()

# List of illegal characters to check (excluding dot)
illegal_chars="\\?\\|,\\*\\\\><:"

# Read each line in the file /tmp/odfailures
while IFS= read -r line; do
  # Extract the last component (filename or folder name)
  component=$(basename "$line")
  
  # Check for leading or trailing spaces
  leading_space=""
  trailing_space=""
  
  # Check for leading space
  if [[ "${component}" =~ ^\  ]]; then
    leading_space="yes"
  fi

  # Check for trailing space
  trimmed_component="${component%"${component##*[![:space:]]}"}" # Remove trailing spaces
  if [[ "$trimmed_component" != "$component" ]]; then
    trailing_space="yes"
  fi

  # Detect illegal characters
  illegal_char_found=""
  if [[ "$component" =~ [$illegal_chars] ]]; then
    illegal_char_found=$(echo "$component" | grep -o -E "[$illegal_chars]" | head -n 1)
  fi

  # If there is an issue, add it to the list of invalid items
  if [[ -n "$leading_space" ]] || [[ -n "$trailing_space" ]] || [[ -n "$illegal_char_found" ]]; then
    LIST_ITEMS+=("$component")

    # Debug output for this component
    echo "Invalid: '$component'"
    if [[ -n "$leading_space" ]]; then
      echo "-> Leading space detected."
    fi
    if [[ -n "$trailing_space" ]]; then
      echo "-> Trailing space detected."
    fi
    if [[ -n "$illegal_char_found" ]]; then
      echo "-> Contains illegal character(s): $illegal_char_found"
    fi
  fi
done < /tmp/odfailures

# Debug: Print the final LIST_ITEMS array contents
echo ""
echo "List of items to be shown in the dialog:"
for item in "${LIST_ITEMS[@]}"; do
  echo "$item"
done

# Prepare the arguments for SwiftDialog
DIALOG_ARGS=()
for item in "${LIST_ITEMS[@]}"; do
  DIALOG_ARGS+=("--listitem" "$item")
done

# If we found an illegal character, update the status message
if [[ -n "$illegal_char_found" ]]; then
  STATUS_MESSAGE="Contains illegal character(s): $illegal_char_found"
else
  STATUS_MESSAGE="No illegal characters found"
fi

# Debugging: Print the final arguments to be passed to Dialog
echo "Arguments passed to SwiftDialog: ${DIALOG_ARGS[@]}"

# Run SwiftDialog with dynamic list and status message
"$DIALOG" \
  --title "Select a File" \
  --message "$STATUS_MESSAGE" \
  --icon "/System/Applications/App Store.app/Contents/Resources/AppIcon.icns" \
  "${DIALOG_ARGS[@]}" \
  --button1text "OK" \
  --button2text "Cancel"

# Capture the exit status of the SwiftDialog command
DIALOG_EXIT_STATUS=$?

# Print the exit status to debug
echo "SwiftDialog exit status: $DIALOG_EXIT_STATUS"

# Check the exit status to determine which button was pressed
if [[ $DIALOG_EXIT_STATUS -eq 0 ]]; then
  echo "User pressed OK"
elif [[ $DIALOG_EXIT_STATUS -eq 2 ]]; then
  echo "User pressed Cancel"
else
  echo "No button pressed or dialog closed"
fi
