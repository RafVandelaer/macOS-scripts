#!/bin/zsh


#############################################################################################################
#                                      Created by Raf Vandelaer                                             #
#                                                                                                           #
#                    Helper script to download the auto updater and run it with Intune                      #
#                       Run script as signed-in user : No                                                   #
#                       Hide script notifications on devices : No(?)                                        #
#                       Script frequency : Weekly                                                           #
#                       Number of times to retry if script fails : 3                                        #
#                                                                                                           #
#                                                                                                           #
#############################################################################################################


########################################### Parameters to modify #########################################################

interactiveMode="${4:="2"}"                                                     # Parameter 4: Interactive Mode [ 0 (Completely Silent) | 1 (Silent Discovery, Interactive Patching) | 2 (Full Interactive) (default) ]
ignoredLabels="${5:=""}"                                                        # Parameter 5: A space-separated list of Installomator labels to ignore (i.e., "microsoft* googlechrome* jamfconnect zoom* 1password* firefox* swiftdialog")
requiredLabels="${6:=""}"                                                       # Parameter 6: A space-separated list of required Installomator labels (i.e., "firefoxpkg_intl")
optionalLabels="${7:=""}"                                                       # Parameter 7: A space-separated list of optional Installomator labels (i.e., "renew") ** Does not support wildcards **
installomatorOptions="${8:-""}"                                                 # Parameter 8: A space-separated list of options to override default Installomator options (i.e., BLOCKING_PROCESS_ACTION=prompt_user NOTIFY=silent LOGO=appstore)
maxDeferrals="${9:-"3"}" 

##################################################################################################

#vars for our helper script
dir="/Users/Shared/Lab9Pro/auto-app-updater"
scriptname="/auto-app-updater.zsh"
fullpath=$dir$scriptname
scriptURL="https://raw.githubusercontent.com/RafVandelaer/macOS-scripts/main/Intune-fundamentals/Auto%20app%20updater/auto-app-updater.zsh"

mkdir $dir

function downloadAndRun {
    echo "Downloading new file and executing."
     curl -sL $scriptURL | md5 > $dir/auto-app-updater.md5
    # Download the script from the given URL
     curl -o $fullpath $scriptURL 
    # Make the script executable
     chmod +x $fullpath
    #Execute the script
      $dir/auto-app-updater.zsh null null null $interactiveMode $ignoredLabels $requiredLabels $optionalLabels $installomatorOptions $maxDeferrals

}

#checking if file exists
if [ -f "$dir/auto-app-updater.md5" ]; then

    #checking old and new MD5 of file
    storedMD5=$(<"$dir/auto-app-updater.md5")
    newMD5=$(curl -sL $scriptURL | md5)
    if [[ "$storedMD5" == "$newMD5" ]]; then
        echo "Same file on server, not downloading..."
        #if md5 are the same, no need to download again.
        #Execute the script
        $dir/auto-app-updater.zsh null null null $interactiveMode $ignoredLabels $requiredLabels $optionalLabels $installomatorOptions $maxDeferrals
    else
        #other md5 -> need to download newer script and change the stored MD5
       downloadAndRun
    fi
  
else 
    #if  no md5 available -> creating for future checks, downloading and running script
   downloadAndRun
fi

exit 0
