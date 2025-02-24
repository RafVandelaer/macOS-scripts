#!/bin/bash
# Define the illegal characters to check, without the dot (.)
# In the sed expression, we need to escape the special ones.
illegal_chars="\\?\\|,\\*\\\\><:"

# Define the full path to SwiftDialog
DIALOG="/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog"

# Initialize an empty array to hold invalid items
LIST_ITEMS=()

while IFS= read -r line; do
  # Extract the last component (filename or folder name)
  component=$(basename "$line")
  
  # Check if the component starts with a space, ends with a space, or contains any illegal character
  if [[ "$component" =~ ^[[:space:]] ]] || [[ "$component" =~ [[:space:]]$ ]] || [[ "$component" =~ [\?\|,\\\*\>\<:] ]]; then
    LIST_ITEMS+=("$component")
    
    # Debug output for this component
    echo "Invalid: '$component'"
    if [[ "$component" =~ ^[[:space:]] ]]; then
      echo "-> Leading space detected."
    fi
    if [[ "$component" =~ [[:space:]]$ ]]; then
      echo "-> Trailing space detected."
    fi
    if [[ "$component" =~ [\?\|,\\\*\>\<:] ]]; then
      specials=$(echo "$component" | grep -o -E "[\?\|,\\\*\>\<:]" | sort -u | tr '\n' ', ' | sed 's/, $//')
      echo "-> Contains illegal character(s): $specials"
    fi
  fi
done < /tmp/odfailures

echo ""
echo "List of items to be shown in the dialog:"
for item in "${LIST_ITEMS[@]}"; do
  echo "$item"
done

# Prepare the arguments for SwiftDialog, replacing each illegal character with markers.
DIALOG_ARGS=()
for item in "${LIST_ITEMS[@]}"; do
  # Replace every illegal character (except dot) with the same character wrapped in ❗ symbols.
  highlighted=$(echo "$item" | sed -E "s/([$illegal_chars])/❗\1❗/g")
  
  # Here we simply pass the modified string; no HTML wrapping.
  DIALOG_ARGS+=("--listitem" "$highlighted")
done

# Debug: Print the final arguments to be passed to SwiftDialog
echo ""
echo "Arguments passed to SwiftDialog: ${DIALOG_ARGS[@]}"

# Run SwiftDialog with dynamic list
RESULT=$("$DIALOG" \
  --title "Select a File" \
  --message "Please choose from the list below:" \
  --icon "/System/Applications/App Store.app/Contents/Resources/AppIcon.icns" \
  "${DIALOG_ARGS[@]}" \
  --button1text "OK" \
  --button2text "Cancel")

# Print the result to see which button was pressed
echo "Dialog result: $RESULT"

if [[ "$RESULT" == *"button1"* ]]; then
  echo "User pressed OK"
elif [[ "$RESULT" == *"button2"* ]]; then
  echo "User pressed Cancel"
else
  echo "No button pressed or dialog closed"
fi
