#!/bin/bash


#    This script started as a simple idea where I wanted to take away
#    much of the scripting needed to set preferences in property list
#    files and move the various settings into an xml file. This would
#    allow those without scripting ability to modify and update which
#    settings to modify. 

#    My goal was to use this script to customize newly enrolled machines
#    so that we can start using the Device Enrollment Program and still
#    standardize on specific settings. But having a separate xml file
#    to reference prevented us from adding it as a script to JAMF PRO. 

#    So I decided I would simply include the xml as payload to the script.
#    With the results directed to stdout, JAMF PRO will automatically 
#    capture the successes or failures in its policy logs.  

#    All xml elements and values are case specific. Follow the structure
#    included below when specifying your desired plist settings.

#    Use at your own risk. 

#    Author:        Andrew Thomson
#    Date:          12-15-2016


#	set if the system should reboot after running script
REBOOT=false


#	for maximum flexibility, preferences can be
#	limited to specific areas: user templates, 
#	existing user profiles, and default system
#	preferences
FUT=true    #	fill user templates
FEU=true    #	fill existing user profiles  
FDL=true    #	fill default library 


#	set preferences paths
SYSTEM_TEMPLATE_PATH="/System/Library/User Template/Non_localized/Library/Preferences/"
DEFAULT_LIBRARY_PATH="/Library/Preferences/"


#	query direcotry for list of local users
LOCAL_USERS=(`/usr/bin/dscl . list /Users UniqueID | awk '$2 > 500 {print $1}'`)


#	read xml payload into variable. the xml payload
#	is read from the tail end of the script immediately 
#	following the string "__XML_FOLLOWS__"
XML_START_LINE=`/usr/bin/awk '/^__XML_FOLLOWS__/ {print NR + 1; exit 0;}' "$0"`
XML_DATA=`/usr/bin/tail +$XML_START_LINE "$0"`


#	query specified preference node from xml payload
function queryPreference() {
	RESULT=`echo $XML_DATA | /usr/bin/xpath "string(/preferences/preference[$1]/$2)" 2> /dev/null`
	echo $RESULT
}


#	verify run as root
if [[ $EUID -ne 0 ]]; then
	echo "ERROR: This script must run with root privileges."
	exit $LINENO
fi


#	verify template and system paths
if [ ! -d "$SYSTEM_TEMPLATE_PATH" ] || [ ! -d "$DEFAULT_LIBRARY_PATH" ]; then
	echo "ERROR: Unable to find one or more paths."
	exit $LINENO
fi


#	use built-in xml command line tool to verify the 
#	xml syntax and formatting
if ! echo $XML_DATA | /usr/bin/xmllint --format - &> /dev/null; then
	echo "ERROR: Invalid XML data. Please verify syntax."
	exit $LINENO
fi


#	get count of preferences found in xml payload 
COUNT=`echo $XML_DATA | /usr/bin/xpath "count(//preference)" 2> /dev/null`; 


#	verify preferences are found
if [ -z $COUNT ]; then
	echo "ERROR: No perferences found."
	exit $LINENO
fi


#	display debug information
if $DEBUG; then echo "PROPERTIES:$COUNT"; fi


#	eunmerate each preference node within the xml
for (( INDEX=1; INDEX<=$COUNT; INDEX++ )); do

	#	parse required xml tag values
	CLASS=`queryPreference "$INDEX" "class"` 
	DOMAIN=`queryPreference "$INDEX" "domain"`
	KEY=`queryPreference "$INDEX" "key"`
	TYPE=`queryPreference "$INDEX" "type"`
	VALUE=`queryPreference "$INDEX" "value"`

	#	process each preference for class of "user"	
	if [ "$CLASS" == "user" ]; then

		#	only write preferences to user templates 
		#	if the fill-user-templates setting is 
		#	enabled
		if $FUT; then 
			#	write preferences to user templates 
			if /usr/bin/defaults write "${SYSTEM_TEMPLATE_PATH%/}/$DOMAIN" $KEY -${TYPE} $VALUE 2> /dev/null; then

				echo "Updated [${SYSTEM_TEMPLATE_PATH%/}/$DOMAIN] with KEY: $KEY TYPE: $TYPE VALUE: $VALUE."
			else

				echo "ERROR: Unable to write key [$KEY] to [${SYSTEM_TEMPLATE_PATH%/}/$DOMAIN]."
			fi
		fi

		#	only write preferences to existing user 
		#	profiles if the fill-existing-user 
		#	setting is enabled
		if $FEU; then
			#	enumerate local users
			for LOCAL_USER in ${LOCAL_USERS[@]}; do

				#	get home directory for local user 
				USER_HOME=`/usr/bin/dscl  . read /Users/$LOCAL_USER NFSHomeDirectory | awk '{ print $2 }'`

				#	skip local user if no existing preferences are found 
				if [ ! -d "${USER_HOME%/}/Library/Preferences" ]; then continue; fi

				#	write preferences to local user profile 
				if /usr/bin/sudo -u $LOCAL_USER /usr/bin/defaults write "${USER_HOME%/}/Library/Preferences/$DOMAIN" $KEY -${TYPE} $VALUE 2> /dev/null; then
				
					echo "Updated [${USER_HOME%/}/Library/Preferences/$DOMAIN with KEY: $KEY TYPE: $TYPE VALUE: $VALUE."
				else
					echo "ERROR: Unable to write key [$KEY] to [${USER_HOME%/}/Library/Preferences/$DOMAIN]."
				fi
			done
		fi

	#	process each preference for class of "system"	
	elif [ "$CLASS" == "system" ]; then

		#	only write preferences to default 
		#	preferences if the fill-default-library 
		#	setting is enabled
		if $FDL; then

			#	write preferences to default library
			if /usr/bin/defaults write "${DEFAULT_LIBRARY_PATH%/}/$DOMAIN" $KEY -${TYPE} $VALUE 2> /dev/null && /bin/chmod 0644 "${DEFAULT_LIBRARY_PATH%/}/$DOMAIN.plist"; then

				echo "Updated [${DEFAULT_LIBRARY_PATH%/}/$DOMAIN] with KEY: $KEY TYPE: $TYPE VALUE: $VALUE."
			else

				echo "ERROR: Unable to write key [$KEY] to [${DEFAULT_LIBRARY_PATH%/}/$DOMAIN]."
			fi
		fi

	fi 
done


#   kill caching of plist entries to
#	force reading of updated settings
/usr/bin/killall cfprefsd


#	depending on the properties you specified, it
#	may be wise to prompt for a reboot. Otherwise
#	only Finder and Dock may need a restart.
if $REBOOT; then
	/usr/bin/osascript -e 'display dialog "This system has been updated and requires a reboot. You have 60 seconds to save your work." with title "Property List Processor" buttons {"Reboot"} default button "Reboot" giving up after 60'
	/sbin/reboot
else 
	if echo $XML_DATA | /usr/bin/grep -i "com.apple.finder" &> /dev/null; then /usr/bin/killall Finder; fi
	if echo $XML_DATA | /usr/bin/grep -i "com.apple.dock" &> /dev/null; then /usr/bin/killall Dock; fi
fi


#	exit script with return code
exit $? 


#	the xml payload that follows can be modified to suit
#	your company's custom settings. the xml data below is
#	case-specific so keep that in mind.


#	I compiled the xml data below from differnt versions of
#	macOS and may not be suitable for all systems. use at
#	your own risk.
 

__XML_FOLLOWS__
<?xml version="1.0" encoding="UTF-8"?>
<preferences>
	<preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>_FXShowPosixPathInTitle</key>
		<type>bool</type>
		<value>true</value>
		<note>Finder: PathInTitle</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>_FXSortFoldersFirst</key>
		<type>bool</type>
		<value>true</value>
		<note>Finder: FoldersOnTop</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>FXDefaultSearchScope</key>
		<type>string</type>
		<value>SCcf</value>
		<note>Finder: SearchCurrentFolder</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>ShowPathBar</key>
		<type>bool</type>
		<value>true</value>
		<note>Finder: ShowPathBar</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>ShowStatusBar</key>
		<type>bool</type>
		<value>true</value>
		<note>Finder: ShowStatusBar</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>NewWindowTarget</key>
		<type>string</type>
		<value>PfHm</value>
		<note>Finder: WindowOpensHomeFolder</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>FXPreferredViewStyle</key>
		<type>string</type>
		<value>Nlsv</value>
		<note>Finder: WindowListView</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.dock</domain>
		<key>minimize-to-application</key>
		<type>bool</type>
		<value>true</value>
		<note>Dock: MinimizeToAppIcon</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.dock</domain>
		<key>wvous-br-corner</key>
		<type>int</type>
		<value>6</value>
		<note>Dock: BottomRightBlockScreenSaver</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.dock</domain>
		<key>wvous-br-modifier</key>
		<type>int</type>
		<value>0</value>
		<note>Dock: BottomRightBlockScreenSaver</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.dock</domain>
		<key>wvous-bl-corner</key>
		<type>int</type>
		<value>5</value>
		<note>Dock: BottomLeftStartScreenSaver</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.dock</domain>
		<key>wvous-bl-modifier</key>
		<type>int</type>
		<value>0</value>
		<note>Dock: BottomLeftStartScreenSaver</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.desktopservices</domain>
		<key>DSDontWriteNetworkStores</key>
		<type>bool</type>
		<value>true</value>
		<note>Desktop: DontSaveAttributesNet</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.desktopservices</domain>
		<key>DSDontWriteUSBStores</key>
		<type>bool</type>
		<value>true</value>
		<note>Desktop: DontSaveAttributesUSB</note>
	</preference>	
	<preference>
		<class>user</class>
		<domain>com.apple.SetupAssistant</domain>
		<key>DidSeeApplePaySetup</key>
		<type>bool</type>
		<value>true</value>
		<note>Setup Supress: ApplePay</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.SetupAssistant</domain>
		<key>DidSeeAvatarSetup</key>
		<type>bool</type>
		<value>true</value>
		<note>Setup Supress: Avatar</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.SetupAssistant</domain>
		<key>DidSeeCloudSetup</key>
		<type>bool</type>
		<value>true</value>
		<note>Setup Supress: iCloud</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.SetupAssistant</domain>
		<key>DidSeeSiriSetup</key>
		<type>bool</type>
		<value>true</value>
		<note>Setup Supress: Siri</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.SetupAssistant</domain>
		<key>DidSeeSyncSetup</key>
		<type>bool</type>
		<value>true</value>
		<note>Setup Supress: Sync</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.SetupAssistant</domain>
		<key>DidSeeSyncSetup2</key>
		<type>bool</type>
		<value>true</value>
		<note>Setup Supress: Setup2</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.SetupAssistant</domain>
		<key>DidSeeTouchIDSetup</key>
		<type>bool</type>
		<value>true</value>
		<note>Setup Supress: TouchID</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.SetupAssistant</domain>
		<key>DidSeeiCloudLoginForStorageServices</key>
		<type>bool</type>
		<value>true</value>
		<note>Setup Supress: Storage</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.SetupAssistant</domain>
		<key>DidSeeiCloudSecuritySetup</key>
		<type>bool</type>
		<value>true</value>
		<note>Setup Supress: Security</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.SetupAssistant</domain>
		<key>GestureMovieSeen</key>
		<type>string</type>
		<value>none</value>
		<note>Setup Supress: Gestures</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.SetupAssistant</domain>
		<key>SkipFirstLoginOptimization</key>
		<type>bool</type>
		<value>true</value>
		<note>Setup Supress: iCloud Version</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.TimeMachine</domain>
		<key>DoNotOfferNewDisksForBackup</key>
		<type>bool</type>
		<value>true</value>
		<note>TimeMachine: NewDisks</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.loginwindow</domain>
		<key>SHOWFULLNAME</key>
		<type>bool</type>
		<value>true</value>
		<note>LoginWindow: FullName</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.loginwindow</domain>
		<key>AdminHostInfo</key>
		<type>string</type>
		<value>DSStatus</value>
		<note>LoginWindow: DSStatus</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.loginwindow</domain>
		<key>LoginwindowLaunchesRelaunchApps</key>
		<type>bool</type>
		<value>false</value>
		<note>LoginWindow: RelaunchApps</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.loginwindow</domain>
		<key>TALLogoutSavesState</key>
		<type>bool</type>
		<value>false</value>
		<note>LoginWindow: SavesState</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.Safari</domain>
		<key>ShowFullURLInS</key>
		<type>bool</type>
		<value>true</value>
		<note>Safari: ShowFullURL</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.Safari</domain>
		<key>ShowStatusBar</key>
		<type>bool</type>
		<value>true</value>
		<note>Safari: StatusBar</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.Safari</domain>
		<key>NewWindowBehavior</key>
		<type>int</type>
		<value>1</value>
		<note>Safari: OpenBlank</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.Safari</domain>
		<key>TabbedBrowsing</key>
		<type>bool</type>
		<value>true</value>
		<note>Safari: EnableTabs</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.Safari</domain>
		<key>OpenExternalLinksInExistingWindow</key>
		<type>bool</type>
		<value>true</value>
		<note>Safari: OpenInTabs</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.Safari</domain>
		<key>OpenNewTabsInFront</key>
		<type>bool</type>
		<value>true</value>
		<note>Safari: NewTabInFront</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.AppleMultitouchTrackpad</domain>
		<key>Clicking</key>
		<type>bool</type>
		<value>true</value>
		<note>Trackpad: TapToClick</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.AppleMultitouchTrackpad</domain>
		<key>TrackpadRightClick</key>
		<type>bool</type>
		<value>true</value>
		<note>Trackpad: RightClick</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.AppleMultitouchTrackpad</domain>
		<key>TrackpadScroll</key>
		<type>bool</type>
		<value>false</value>
		<note>Trackpad: ReverseScroll</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.AppleMultitouchTrackpad</domain>
		<key>HIDScrollZoomModifierMask</key>
		<type>int</type>
		<value>262144</value>
		<note>Trackpad: Zoom</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.AppleBluetoothMultitouch.trackpad</domain>
		<key>Clicking</key>
		<type>bool</type>
		<value>true</value>
		<note>BTTrackpad: TapToClick</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.AppleBluetoothMultitouch.trackpad</domain>
		<key>TrackpadRightClick</key>
		<type>bool</type>
		<value>true</value>
		<note>BTTrackpad: RightClick</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.AppleBluetoothMultitouch.trackpad</domain>
		<key>TrackpadScroll</key>
		<type>bool</type>
		<value>false</value>
		<note>BTTrackpad: ReverseScroll</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.AppleBluetoothMultitouch.trackpad</domain>
		<key>HIDScrollZoomModifierMask</key>
		<type>int</type>
		<value>262144</value>
		<note>BTTrackpad: Zoom</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.universalaccess</domain>
		<key>closeViewScrollWheelToggle</key>
		<type>bool</type>
		<value>true</value>
		<note>UnvAccess: ScrollZoom</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>.GlobalPreferences</domain>
		<key>NSQuitAlwaysKeepsWindows</key>
		<type>bool</type>
		<value>false</value>
		<note>GlobDom: DontKeepWindows</note>
	</preference>
	<preference>
		<class>user</class>
		<domain>com.apple.CrashReporter</domain>
		<key>DialogType</key>
		<type>string</type>
		<value>none</value>
		<note>CrashReport: DontWriteCrashReports</note>
	</preference>


	<!--    start system class preferences    --> 


	<preference>
		<class>system</class>
		<domain>com.apple.loginwindow</domain>
		<key>SHOWFULLNAME</key>
		<type>bool</type>
		<value>true</value>
		<note>LoginWindow: FullName</note>
	</preference>
	<preference>
		<class>system</class>
		<domain>com.apple.loginwindow</domain>
		<key>AdminHostInfo</key>
		<type>string</type>
		<value>DSStatus</value>
		<note>LoginWindow: Options</note>
	</preference>
	<preference>
		<class>system</class>
		<domain>com.apple.NetworkAuthorization</domain>
		<key>UseShortName</key>
		<type>bool</type>
		<value>true</value>
		<note>NetAuth: ShortName</note>
	</preference>
	<preference>
		<class>system</class>
		<domain>com.apple.AppleMultitouchTrackpad</domain>
		<key>Clicking</key>
		<type>bool</type>
		<value>true</value>
		<note>Trackpad: TapToClick</note>
	</preference>
	<preference>
		<class>system</class>
		<domain>com.apple.AppleMultitouchTrackpad</domain>
		<key>TrackpadRightClick</key>
		<type>bool</type>
		<value>true</value>
		<note>Trackpad: RightClick</note>
	</preference>
	<preference>
		<class>system</class>
		<domain>com.apple.AppleBluetoothMultitouch.trackpad</domain>
		<key>Clicking</key>
		<type>bool</type>
		<value>true</value>
		<note>BTTrackpad: TapToClick</note>
	</preference>
	<preference>
		<class>system</class>
		<domain>com.apple.AppleBluetoothMultitouch.trackpad</domain>
		<key>TrackpadRightClick</key>
		<type>bool</type>
		<value>true</value>
		<note>BTTrackpad: RightClick</note>
	</preference>
	<preference>
		<class>system</class>
		<domain>com.apple.AppleBluetoothMultitouch.trackpad</domain>
		<key>TrackpadScroll</key>
		<type>bool</type>
		<value>false</value>
		<note>BTTrackpad: ReverseScroll</note>
	</preference>
</preferences>