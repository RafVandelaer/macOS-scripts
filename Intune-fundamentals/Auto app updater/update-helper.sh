#!/bin/zsh

#TODO: check if file exists, otherwise download. Maybe sleep after download (first run?)
#TODO: Parameters meegeven adhv de klant



#############################################################################################################
#                                      Created by Raf Vandelaer                                             #
#                                                                                                           #
#                    Helper script to download the auto updater and run it with Intune                      #
#                       Run script as signed-in user : No                                                   #
#                       Hide script notifications on devices : No(?)                                          #
#                       Script frequency : Weekly                                                           #
#                       Number of times to retry if script fails : 3                                        #
#                                                                                                           #
#                                                                                                           #
#############################################################################################################


########################################### Parameters om aan te passen #########################################################

interactiveMode="${4:="2"}"                                                     # Parameter 4: Interactive Mode [ 0 (Completely Silent) | 1 (Silent Discovery, Interactive Patching) | 2 (Full Interactive) (default) ]
ignoredLabels="${5:=""}"                                                        # Parameter 5: A space-separated list of Installomator labels to ignore (i.e., "microsoft* googlechrome* jamfconnect zoom* 1password* firefox* swiftdialog")
requiredLabels="${6:=""}"                                                       # Parameter 6: A space-separated list of required Installomator labels (i.e., "firefoxpkg_intl")
optionalLabels="${7:=""}"                                                       # Parameter 7: A space-separated list of optional Installomator labels (i.e., "renew") ** Does not support wildcards **
installomatorOptions="${8:-""}"                                                 # Parameter 8: A space-separated list of options to override default Installomator options (i.e., BLOCKING_PROCESS_ACTION=prompt_user NOTIFY=silent LOGO=appstore)
maxDeferrals="${9:-"3"}" 

mkdir /Users/Shared/Lab9Pro

# Download the script from the given URL
curl -o /Users/Shared/Lab9Pro/auto-app-updater.zsh https://raw.githubusercontent.com/RafVandelaer/macOS-scripts/main/Intune-fundamentals/Auto%20app%20updater/auto-app-updater.zsh

# Make the script executable
chmod +x /Users/Shared/Lab9Pro/auto-app-updater.zsh

# Execute the script
/Users/Shared/Lab9Pro/auto-app-updater.zsh null null null $interactiveMode $ignoredLabels $requiredLabels $optionalLabels $installomatorOptions $maxDeferrals

exit 0
