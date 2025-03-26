#!/bin/bash
#Log, Configs, WEB URL

weburl="https://www.dropbox.com/scl/fi/dnmm9xdis41x55j73wsw1/FortiClientVPNSetup_7.4.2.1717_macosx.dmg?rlkey=13hu0rtc9rjc3j8lqse8nsewz&d=1" # Replace with your own URL path

FortiClient_Installerversion="7421717" #Enter your FortiClient installer version using version and build number. e.g FortiClient 7.2.2 would be value "7220776"

# Configuration variables - modify these as needed
VPN_NAME="NAME"
VPN_SSO_ENABLED=1              # 1 for enabled, 0 for disabled
VPN_SERVER="DOMAIN.COM"
VPN_SERVER_PORT=10000
VPN_USE_EXTERNAL_BROWSER=1     # 1 for enabled, 0 for disabled


# Please modify below values based on the new FCT installer feature set created on the EMS, and please don't modify other part of the script.

av="0"	# Enter 0 when Malware feature is disabled in the FortiClient installer
af="0"	# Enter 0 when Application Firewall  feature is disabled in the FortiClient installer
sb="0"	# Enter 0 when Advanced Persistent Threat (APT) components feature is disabled in the FortiClient installer
sra="0"	# Enter 0 when Secure Access Architecture Components feature is disabled in the FortiClient installer
sso="1"	# Enter 0 when Single Sign-On Mobility Agent feature is disabled in the FortiClient installer
vs="0"	# Enter 0 when vulnerability Scan feature is disabled in the FortiClient installer
wf="0"	# Enter 0 when Web Filtering feature is disabled in the FortiClient installer

# FortiClient 6.4 does not have ZTNA feature, and FCT 7.0 or higher version will always install ZTNA  feature because of the mantis 0825169.

# ztna="1" # You should keep this value as "1" until the mantis 0825169 get fixed.

# Please set uninstall value to 1 for FortiClient un-installatiion only. By default, the uninstall value is '0' for deployment.
uninstall="0"

# For 7.2.3, FCT uses ftgdagent process for webfiltering by default.
# Enabling the new webfilter with https mode will install a new certificate in the system keychain access, which requires admin's permission to trust the certificate.
# set httpsmode to "0" to disable https mode inspection (default action), set httpsmode to "1" to enable.
httpsmode="0"

tempdir="/tmp/Installer"
MOUNT_POINT="$tempdir/mount"

appname="FortiClient" # The name of our App deployment script (also used for Octory monitor)

logandmetadir="/var/Log/$appname"
log="$logandmetadir/$appname.log"

function startLog() {
    ## Check if the log directory has been created
    if [ ! -d "$logandmetadir" ]; then
        ## Creating Metadirectory
        echo "$(date) | Creating [$logandmetadir] to store metadata"
        mkdir -p "$logandmetadir"
    fi
}

## Install DMG Function
function installDMG () {
    cd "$tempdir"
    mkdir -p $MOUNT_POINT
    echo "made directory $MOUNT_POINT"
    echo $PWD

    hdiutil attach installer.dmg -mountpoint $MOUNT_POINT -noverify -nobrowse -noautoopen
    sudo /usr/sbin/installer -pkg $MOUNT_POINT/Install.mpkg -target /
    if [[ $httpsmode == 0 ]]; then
        DisableHTTPSMode
    else
        echo "Https Mode is enabled."
    fi
    echo "New FCT Has been installed successfully"
    hdiutil detach $MOUNT_POINT
    echo "Unmount FCT mount point"
}

function downloadApp () {
    rm -rf $tempdir
    mkdir -p $tempdir
    cd "$tempdir"
    echo "Tries to Download FortiClient deployment Package from MIS EMS server"
    curl -k --connect-timeout 30 --retry 5 --retry-delay 60 -L -J -O "$weburl"
    if [ $? -eq 0 ]; then

        # We have downloaded a file, we need to know what the file is called and what type of file it is
        tempSearchPath="$tempdir/"
        for f in $tempSearchPath*; do
            tempfile=$f
            echo "tempfile 0 $tempfile"
        done

        mv "$tempfile" "$tempdir/installer.dmg"
        tempfile="$tempdir/installer.dmg"

    else
        echo "$(date) | Failure to download [$weburl] to [$tempfile]"
        exit 1
    fi

    sudo /Applications/FortiClientUninstaller.app/Contents/Library/LaunchServices/com.fortinet.forticlient.uninstall_helper upgrade-uninstall
    echo "FCT Mac has been uninstalled"
}

function UninstallFCT () {
    sudo /Applications/FortiClientUninstaller.app/Contents/Library/LaunchServices/com.fortinet.forticlient.uninstall_helper upgrade-uninstall
    echo "FCT Mac has been uninstalled"
}
function DisableHTTPSMode () {
    sudo rm /Library/Application\ Support/Fortinet/FortiClient/data/enable_wf_https_mode
    echo "https mode disabled"
}

if [ $EUID -ne 0 ] || [ "$(id -u)" != "0" ]; then
    echo "Please run as root"
    exit 1
fi

startLog
echo ""
echo "##################################################################"
echo "# $(date) | Logging Deployment of FortiCLient Mac"
echo "##################################################################"
echo ""
echo $4

if [[ $uninstall == 1 ]]; then
    UninstallFCT
    exit 0
elif [[ $uninstall == 0 ]]; then

    # Verifying FortiClient has been already Installed or not.
    if open -Ra "FortiClient" ; then

    # Checking FortiClient Version
    FortiClient_version="$(grep -A1 'version=' /Library/Application\ Support/Fortinet/FortiClient/conf/fctinfo | sed 's/.*=//' | tr -d '.')"
    echo "Current FortiClient Version = ${FortiClient_version}"

        # Comparing FortiClient version
        if [[ "$FortiClient_version" == *"$FortiClient_Installerversion"* ]]; then

            #Checking FCT is only-VPN or Full version
            if [ -f "/Library/Application Support/Fortinet/FortiClient/bin/epctrl" ]; then

                # Extracting feature values from config.plist file
                ep_av="$(grep -A1 '<key>AntiVirus</key>' /Library/Application\ Support/Fortinet/FortiClient/conf/custom.plist)"
                ep_af="$(grep -A1 '<key>ApplicationFirewall</key>' /Library/Application\ Support/Fortinet/FortiClient/conf/custom.plist)"
                ep_sb="$(grep -A1 '<key>Sandboxing</key>' /Library/Application\ Support/Fortinet/FortiClient/conf/custom.plist)"
                ep_sra="$(grep -A1 '<key>SecureRemoteAccess</key>' /Library/Application\ Support/Fortinet/FortiClient/conf/custom.plist)"
                ep_sso="$(grep -A1 '<key>SingleSignOn</key>' /Library/Application\ Support/Fortinet/FortiClient/conf/custom.plist)"
                ep_vs="$(grep -A1 '<key>VulnerabilityScan</key>' /Library/Application\ Support/Fortinet/FortiClient/conf/custom.plist)"
                ep_wf="$(grep -A1 '<key>WebFiltering</key>' /Library/Application\ Support/Fortinet/FortiClient/conf/custom.plist)"

                # You maybe uncomment this once the mantis 0825169 get fixed.
                # ep_ztna="$(grep -A1 '<key>ZeroTrustNetworkAccess</key>' /Library/Application\ Support/Fortinet/FortiClient/conf/custom.plist)"
                # ep_ztna="<key>ZeroTrustNetworkAccess</key><integer>1</integer>"  # Remove this hardcoded ep_ztna once the mantis 0825169 get fixed.

                if [[ -n "$ep_av" ]]; then
                e_av=1
                else
                e_av=0
                fi
                if [[ -n "$ep_af" ]]; then
                e_af=1
                else
                e_af=0
                fi
                if [[ -n "$ep_sb" ]]; then
                e_sb=1
                else
                e_sb=0
                fi
                if [[ -n "$ep_sra" ]]; then
                e_sra=1
                else
                e_sra=0
                fi
                if [[ -n "$ep_sso" ]]; then
                e_sso=1
                else
                e_sso=0
                fi
                if [[ -n "$ep_vs" ]]; then
                e_vs=1
                else
                e_vs=0
                fi
                if [[ -n "$ep_wf" ]]; then
                e_wf=1
                else
                e_wf=0
                fi
                #if [[ -n "$ep_ztna" ]]; then
                #  e_ztna=1
                #else
                #  e_ztna=0
                #fi



            # Comparing Feature set
                if [[ $av == $e_av && $af == $e_af && $sb == $e_sb && $sra == $e_sra && $sso == $e_sso && $vs == $e_vs && $wf == $e_wf ]]; then
                    echo "Same FortiClient has already been installed on the endpoint"
                else
                echo "Currently installed FortiClient features are shown below:"
                echo "##########################################################"
                if [[ -n $ep_av ]]; then
                    echo "Malware feature"
                fi
                if [[ -n $ep_af ]]; then
                    echo "Application Firewall"
                fi
                if [[ -n $ep_sb ]]; then
                    echo "Advanced Persistent Threat (APT) components"
                fi
                if [[ -n $ep_sra ]]; then
                    echo "Secure Access Architecture Components"
                fi
                if [[ -n $ep_sso ]]; then
                    echo "Single Sign-On Mobility Agent"
                fi
                if [[ -n $ep_vs ]]; then
                    echo "Vulnerability Scan"
                fi
                if [[ -n $ep_wf ]]; then
                    echo "Web Filtering"
                fi
                # if [[ -n $ep_ztna ]]; then
                #    echo "Zero Trust Network Access"
                # fi
                echo "##########################################################"
                echo "FortiClient with different feature set would be installed on the endpoint."
                echo "Removing old FortiClient and installing new FortiClient."
                downloadApp
                installDMG
                fi
            else
                echo "FortiClient only-VPN version has been installed on the endpoint. Upgrading FortiClient only-VPN version to Full Version"
                downloadApp
                installDMG
            fi
        else
            echo "FortiClient with different version has been installed on the endpoint. Removing old FortiClient and installing new FortiClient"
            downloadApp
            installDMG
        fi
    else
        echo "No FortiClient is installed on the endpoint. Installing FortiClient now"
        downloadApp
        installDMG
    fi
else
    echo "uninstall value can only be 0 or 1!"
fi




# Output file path
OUTPUT_FILE="/Library/Application Support/Fortinet/Forticlient/conf/vpn.plist"


# Create directory if it doesn't exist
mkdir -p "/Library/Application Support/Fortinet/Forticlient/conf"

# Create the plist file
cat > "$OUTPUT_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AutoConnectOnInstall</key>
	<integer>0</integer>
	<key>AutoStartVPN</key>
	<string></string>
	<key>AutoStartVPNOnlyOffNet</key>
	<integer>0</integer>
	<key>DNSServiceResettingInterval</key>
	<integer>0</integer>
	<key>DisableConnectDisconnect</key>
	<integer>0</integer>
	<key>DisallowPersonalVPN</key>
	<integer>0</integer>
	<key>DtlsMTU</key>
	<integer>1100</integer>
	<key>EnableIPSec</key>
	<integer>1</integer>
	<key>EnableSSL</key>
	<integer>1</integer>
	<key>InheritLocalDNS</key>
	<integer>0</integer>
	<key>IpsecDisallowInvalidServCert</key>
	<integer>0</integer>
	<key>IpsecShouldBlockIpv6</key>
	<integer>1</integer>
	<key>MinimizeOnConnect</key>
	<integer>0</integer>
	<key>NetworkLockdownAppException</key>
	<array/>
	<key>NetworkLockdownDomainException</key>
	<array/>
	<key>NetworkLockdownEnabled</key>
	<integer>0</integer>
	<key>NetworkLockdownGracePeriod</key>
	<integer>120</integer>
	<key>NetworkLockdownICDBException</key>
	<array/>
	<key>NetworkLockdownIPException</key>
	<array/>
	<key>NetworkLockdownMaxAttempts</key>
	<integer>3</integer>
	<key>PreferDtlsTunnel</key>
	<integer>0</integer>
	<key>Profiles</key>
	<dict>
		<key>$VPN_NAME</key>
		<dict>
			<key>AllowAutoConnect</key>
			<integer>0</integer>
			<key>AllowKeepRunning</key>
			<integer>0</integer>
			<key>AllowSavePassword</key>
			<integer>0</integer>
			<key>AllowedTags</key>
			<string></string>
			<key>AuthInfo</key>
			<string></string>
			<key>CertCNMatchType</key>
			<string></string>
			<key>CertCNPattern</key>
			<string></string>
			<key>CertIssuerMatchType</key>
			<string></string>
			<key>CertIssuerPattern</key>
			<string></string>
			<key>Comment</key>
			<string></string>
			<key>DualStackEnabled</key>
			<integer>0</integer>
			<key>EmsAllowAutoConnect</key>
			<integer>0</integer>
			<key>EmsAllowKeepRunning</key>
			<integer>0</integer>
			<key>EmsAllowSavePassword</key>
			<integer>0</integer>
			<key>EnableCustomPort</key>
			<integer>1</integer>
			<key>GotSettingsFromFGT</key>
			<integer>0</integer>
			<key>HostcheckFailWarning</key>
			<string></string>
			<key>KeepRunning</key>
			<integer>0</integer>
			<key>KeepRunningMaxRetry</key>
			<integer>0</integer>
			<key>Name</key>
			<string>$VPN_NAME</string>
			<key>ProhibitedTags</key>
			<string></string>
			<key>PromptForAuthentication</key>
			<integer>0</integer>
			<key>PromptForCertificate</key>
			<integer>0</integer>
			<key>ProxyAddress</key>
			<string></string>
			<key>ProxyPassword</key>
			<string></string>
			<key>ProxyPort</key>
			<integer>0</integer>
			<key>ProxyUser</key>
			<string></string>
			<key>ReadOnly</key>
			<integer>0</integer>
			<key>RedundantSortMethod</key>
			<integer>0</integer>
			<key>SSLVpnMethod</key>
			<integer>0</integer>
			<key>SSOEnabled</key>
			<integer>$VPN_SSO_ENABLED</integer>
			<key>SamlFQDNConsistency</key>
			<integer>0</integer>
			<key>SavePassword</key>
			<integer>0</integer>
			<key>SaveUsername</key>
			<integer>0</integer>
			<key>Server</key>
			<string>$VPN_SERVER</string>
			<key>ServerPort</key>
			<integer>$VPN_SERVER_PORT</integer>
			<key>ShowPasscode</key>
			<integer>0</integer>
			<key>SslVpnType</key>
			<string></string>
			<key>TrafficControl</key>
			<dict>
				<key>Apps</key>
				<array/>
				<key>Enabled</key>
				<false/>
				<key>FQDNs</key>
				<array/>
				<key>Mode</key>
				<integer>2</integer>
			</dict>
			<key>UseExternalBrowser</key>
			<integer>$VPN_USE_EXTERNAL_BROWSER</integer>
			<key>User</key>
			<string></string>
			<key>VpnType</key>
			<integer>0</integer>
			<key>WarnInvalidServerCertificate</key>
			<integer>1</integer>
		</dict>
	</dict>
	<key>SecureRemoteAccess</key>
	<integer>0</integer>
	<key>SslDisallowInvalidServCert</key>
	<integer>0</integer>
	<key>SslShouldBlockIpv6</key>
	<integer>1</integer>
	<key>SuppressVpnNotification</key>
	<integer>0</integer>
	<key>VpnCurrentConnect</key>
	<string></string>
	<key>VpnCurrentConnectType</key>
	<string></string>
	<key>WarnInvalidServerCertificate</key>
	<integer>1</integer>
</dict>
</plist>
EOF



# Ensure proper permissions for the file
chmod 644 /Library/Application\ Support/Fortinet/FortiClient/conf/vpn.plist

echo "vpn.plist created successfully!"