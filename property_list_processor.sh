#!/bin/bash


#    This script started as a simple idea where I wanted to take away
#    much of the scripting needed to set preferences in property list
#    files. To do this, I moved the various settings into xml format 
#    and included them as payload at the tail end of the script. I thought 
#    doing so would be more efficient and allow non-scripters the ability
#    to modify preferences without having to alter any bash syntax. 

#    For maximum flexiblity, I added the TARGET parameter so the 
#    script could be used from within a package file to affect non-booted
#    volumes during the imaging or upgrade process.

#    Author:        Andrew Thomson
#    Date:          12-15-2016
#    GitHub:        https://github.com/thomsontown



#	for maximum flexibility, preferences can be
#	limited to specific areas: user templates, 
#	existing user profiles, and default system
#	preferences
FUT=true    #	fill user templates
FEU=true    #	fill existing user profiles  
FDL=true    #	fill default library 


#	set if the system should reboot after running script
REBOOT=false


#	if target not specified, then target is /
TARGET=${3:-/}


#	set preferences paths
SYSTEM_TEMPLATE_PATH="${TARGET%/}/System/Library/User Template/Non_localized/Library/Preferences/"
DEFAULT_LIBRARY_PATH="${TARGET%/}/Library/Preferences/"


#	verify run as root
if [[ $EUID -ne 0 ]]; then
	(>&2 echo "ERROR: This script must run with root privileges.")
	exit $LINENO
fi


#	get list of home directories from target
for USER_PLIST in "${TARGET%/}"/var/db/dslocal/nodes/Default/users/*.plist; do
	HOME_DIRECTORIES+=(`/usr/bin/defaults read "$USER_PLIST" home | /usr/bin/awk -F'"' '{getline;print $2;exit}' 2> /dev/null`)
done


#	eliminate home directories without existing preferences
for HOME_INDEX in ${!HOME_DIRECTORIES[@]}; do
	if [ ! -d "${TARGET%/}${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences" ]; then
		unset HOME_DIRECTORIES[$HOME_INDEX] 
	fi
done


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


#	verify template and system paths
if [ ! -d "$SYSTEM_TEMPLATE_PATH" ] || [ ! -d "$DEFAULT_LIBRARY_PATH" ]; then
	(>&2 echo "ERROR: Unable to find one or more paths.")
	exit $LINENO
fi


#	use built-in xml command line tool to verify the 
#	xml syntax and formatting
if ! echo $XML_DATA | /usr/bin/xmllint --format - &> /dev/null; then
	(>&2 echo "ERROR: Invalid XML data. Please verify syntax.")
	exit $LINENO
fi


#	get count of preferences found in xml payload 
COUNT=`echo $XML_DATA | /usr/bin/xpath "count(//preference)" 2> /dev/null`; 


#	verify preferences are found
if [ -z $COUNT ]; then
	(>&2 echo "ERROR: No perferences found.")
	exit $LINENO
fi


#	display debug information
if $DEBUG; then echo "PROPERTIES:$COUNT"; fi
if $DEBUG; then echo "PROFILES:${#HOME_DIRECTORIES[@]}"; fi


#	eunmerate each preference node within the xml
for (( PREF_INDEX=1; PREF_INDEX<=$COUNT; PREF_INDEX++ )); do

	#	parse required xml tag values
	CLASS=`queryPreference "$PREF_INDEX" "class"` 
	DOMAIN=`queryPreference "$PREF_INDEX" "domain"`
	KEY=`queryPreference "$PREF_INDEX" "key"`
	TYPE=`queryPreference "$PREF_INDEX" "type"`
	VALUE=`queryPreference "$PREF_INDEX" "value"`

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

				(>&2 echo "ERROR: Unable to write key [$KEY] to [${SYSTEM_TEMPLATE_PATH%/}/$DOMAIN].")
			fi
		fi

		#	only write preferences to existing user 
		#	profiles if the fill-existing-user 
		#	setting is enabled
		if $FEU; then
			#	enumerate local users
			for HOME_INDEX in ${!HOME_DIRECTORIES[@]}; do

				#	get profile user
				OWNER=`/usr/bin/stat -f %u:%g "${TARGET%/}${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/."`

				#	write preferences to local user profile 
				if /usr/bin/defaults write "${TARGET%/}${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/$DOMAIN" $KEY -${TYPE} $VALUE 2> /dev/null; then
					echo "Updated [${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/$DOMAIN] with KEY: $KEY TYPE: $TYPE VALUE: $VALUE."

					#	reset permissions after updating
					/bin/chmod 0755  "${TARGET%/}${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/${DOMAIN}.plist" 2> /dev/null
					/usr/sbin/chown $OWNER "${TARGET%/}${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/${DOMAIN}.plist"	2> /dev/null		
				else
					(>&2 echo "ERROR: Unable to write key [$KEY] to [${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/$DOMAIN].")
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

				(>&2 echo "ERROR: Unable to write key [$KEY] to [${DEFAULT_LIBRARY_PATH%/}/$DOMAIN].")
			fi
		fi

	elif [ "$CLASS" == "byhost" ]; then

		#	only write preferences to existing user 
		#	profiles if the fill-existing-user 
		#	setting is enabled
		if $FEU; then
			#	enumerate local users
			for HOME_INDEX in ${!HOME_DIRECTORIES[@]}; do

				#	get profile user
				OWNER=`/usr/bin/stat -f %u:%g "${TARGET%/}${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/ByHost."`

				#	write preferences to local user profile 
				if /usr/bin/defaults -currentHost write "${TARGET%/}${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/$DOMAIN" $KEY -${TYPE} $VALUE 2> /dev/null; then
					echo "Updated [${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/ByHost/$DOMAIN] with KEY: $KEY TYPE: $TYPE VALUE: $VALUE."

					#	reset permissions after updating
					/bin/chmod 0755  "${TARGET%/}${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/ByHost/${DOMAIN}.plist" 2> /dev/null
					/usr/sbin/chown $OWNER "${TARGET%/}${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/ByHost/${DOMAIN}.plist"	2> /dev/null		
				else
					(>&2 echo "ERROR: Unable to write key [$KEY] to [${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/ByHost/$DOMAIN].")
				fi
			done
		fi

	fi 


	#	add a blank line for each preference
	if $DEBUG && [ "$CLASS" == "user" ]; then echo -e "\r"; fi
done


#	depending on the properties you specified, it
#	may be wise to prompt for a reboot. Otherwise
#	only Finder and Dock may need a restart.
if $REBOOT; then
	/usr/bin/osascript -e 'display dialog "This system has been updated and requires a reboot. You have 60 seconds to save your work." with title "Property List Processor" buttons {"Reboot"} default button "Reboot" giving up after 60'
	/sbin/reboot
else 
	if /usr/bin/pgrep cfprefsd; then /usr/bin/pkill cfprefsd; fi
	if echo $XML_DATA | /usr/bin/grep -i "com.apple.finder" &> /dev/null && /usr/bin/pgrep Finder; then /usr/bin/pkill Finder; fi
	if echo $XML_DATA | /usr/bin/grep -i "com.apple.dock" &> /dev/null&& /usr/bin/pgrep Dock; then /usr/bin/pkill Dock; fi
fi


#	exit script with return code
exit 0 


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
		<domain>.GlobalPreferences</domain>
		<key>NSQuitAlwaysKeepsWindows</key>
		<type>bool</type>
		<value>false</value>
		<comment>Disable saving application states.</comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>.GlobalPreferences</domain>
		<key>AppleActionOnDoubleClick</key>
		<type>string</type>
		<value>Maximize</value>
		<comment>Set action when double-clicking on a window title-bar.</comment>
	</preference>
	<preference>
		<class>user</class>
		<domain>.GlobalPreferences</domain>
		<key>com.apple.trackpad.forceClick</key>
		<type>bool</type>
		<value>false</value>
		<comment></comment>
	</preference>
   <preference>
		<class>user</class>
		<domain>.GlobalPreferences</domain>
		<key>com.apple.swipescrolldirection</key>
		<type>bool</type>
		<value>false</value>
		<comment></comment>
	</preference>
   <preference>
		<class>user</class>
		<domain>.GlobalPreferences</domain>
		<key>NSAutomaticDashSubstitutionEnabled</key>
		<type>bool</type>
		<value>false</value>
		<comment>Disable smart dashes.</comment>
	</preference>
   <preference>
		<class>user</class>
		<domain>.GlobalPreferences</domain>
		<key>NSAutomaticQuoteSubstitutionEnabled</key>
		<type>bool</type>
		<value>false</value>
		<comment>Disable smart quotes.</comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.CrashReporter</domain>
		<key>DialogType</key>
		<type>string</type>
		<value>none</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.desktopservices</domain>
		<key>DSDontWriteNetworkStores</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.desktopservices</domain>
		<key>DSDontWriteUSBStores</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.dock</domain>
		<key>minimize-to-application</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.dock</domain>
		<key>wvous-br-corner</key>
		<type>int</type>
		<value>6</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.dock</domain>
		<key>wvous-br-modifier</key>
		<type>int</type>
		<value>0</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.dock</domain>
		<key>wvous-bl-corner</key>
		<type>int</type>
		<value>5</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.dock</domain>
		<key>wvous-bl-modifier</key>
		<type>int</type>
		<value>0</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.dock</domain>
		<key>wvous-tr-corner</key>
		<type>int</type>
		<value>10</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.dock</domain>
		<key>wvous-tr_modifier</key>
		<type>int</type>
		<value>0</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>_FXShowPosixPathInTitle</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>_FXSortFoldersFirst</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>FXDefaultSearchScope</key>
		<type>string</type>
		<value>SCcf</value>
		<comment>Search current folder by default.</comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>FXPreferredSearchViewStyle</key>
		<type>string</type>
		<value>Nlsv</value>
		<comment>Show file lists by default.</comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>FXPreferredViewStyle</key>
		<type>string</type>
		<value>Nlsv</value>
		<comment>Show file lists by default.</comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>ShowPathBar</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>ShowStatusBar</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.finder</domain>
		<key>NewWindowTarget</key>
		<type>string</type>
		<value>PfHm</value>
		<comment>New window opens to user profile.</comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.loginwindow</domain>
		<key>SHOWFULLNAME</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.loginwindow</domain>
		<key>AdminHostInfo</key>
		<type>string</type>
		<value>DSStatus</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.loginwindow</domain>
		<key>LoginwindowLaunchesRelaunchApps</key>
		<type>bool</type>
		<value>false</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.loginWindow</domain>
		<key>TALLogoutSavesState</key>
		<type>bool</type>
		<value>false</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.Safari</domain>
		<key>ShowFullURLInSmartSearchField</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.Safari</domain>
		<key>ShowStatusBar</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.Safari</domain>
		<key>NewTabBehavior</key>
		<type>int</type>
		<value>1</value>
		<comment>Open new browser tab with blank tab.</comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.Safari</domain>
		<key>NewWindowBehavior</key>
		<type>int</type>
		<value>1</value>
		<comment>Open new browser window with blank tab.</comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.Safari</domain>
		<key>TabbedBrowsing</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.Safari</domain>
		<key>OpenExternalLinksInExistingWindow</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.Safari</domain>
		<key>OpenNewTabsInFront</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.TimeMachine</domain>
		<key>DoNotOfferNewDisksForBackup</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>user</class>
		<domain>com.apple.universalaccess</domain>
		<key>closeViewScrollWheelPreviousToggle</key>
		<type>bool</type>
		<value>true</value>
		<comment>Add Control-Zoom to accessibility.</comment>
	</preference>	
    <preference>
		<class>user</class>
		<domain>com.apple.universalaccess</domain>
		<key>closeViewScrollWheelToggle</key>
		<type>bool</type>
		<value>true</value>
		<comment>Add Control-Zoom to accessibility.</comment>
	</preference>


	<!--    start system class preferences    --> 


    <preference>
		<class>system</class>
		<domain>com.apple.loginwindow</domain>
		<key>SHOWFULLNAME</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>
    <preference>
		<class>system</class>
		<domain>com.apple.loginwindow</domain>
		<key>AdminHostInfo</key>
		<type>string</type>
		<value>DSStatus</value>
		<comment></comment>
	</preference>
    <preference>
		<class>system</class>
		<domain>com.apple.networkauthorization</domain>
		<key>UseShortName</key>
		<type>bool</type>
		<value>true</value>
		<comment></comment>
	</preference>


	<!--    start byhost class preferences    --> 

    <preference>
		<class>byhost</class>
		<domain>.GlobalPreferences</domain>
		<key>com.apple.mouse.tapBehavior</key>
		<type>bool</type>
		<value>true</value>
		<comment>Set tap to click for touchpads.</comment>
	</preference>
</preferences>