#!/bin/zsh

# Pad naar swiftDialog
DIALOG="/usr/local/bin/dialog"

# Controleer of swiftDialog geïnstalleerd is
if [ ! -f "$DIALOG" ]; then
    echo "swiftDialog is niet geïnstalleerd. Installeer het via https://github.com/bartreardon/swiftDialog."
    exit 1
fi


    # FDA is niet ingesteld, toon een swiftDialog pop-up
    "$DIALOG" \
        --title "Volledige schijftoegang vereist" \
        --message "OneDrive heeft volledige schijftoegang nodig voor het synchroniseren van jouw Bureaublad en Documenten mappen.\n\n **Druk op de knop 'Stel in'** om daarna OneDrive aan te vinken.\n\n Of ga naar **Systeeminstellingen > Beveiliging en privacy > Privacy > Volledige schijftoegang**\n\n Je zal OneDrive opnieuw moeten opstarten om de wijzigingen toe te passen." \
        --icon "/Applications/OneDrive.app" \
        --button1text "Stel in"

    # Open de instellingen automatisch (na klikken op "Ik begrijp het")
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

