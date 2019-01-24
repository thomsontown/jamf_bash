#!/bin/bash 


#.   This script was written to run from a JAMF PRO server at login where $3 specifies
#.   the current console user. The setCustomDefaults function reads from XML included
#.   at the end of this script file and processes each setting using the defaults command.
#.   Included in this sample are a series of settings to consider. The XML data can be 
#.   customized to suit your specific needs.  

#.   Author:          Andrew Thomson
#.   Date:            01-23-2019
#.   GitHub:          https://github.com/thomsontown


USERNAME=$3
LOG_PATH="/var/log/imaging_set_custom_defaults.log"


function isRoot () {

	#	verify script run as root
	if [[ $UID -ne 0 ]]; then

		echo "ERROR: Script must run with root privileges." >&2
		echo -e "\\tUSAGE: sudo \"$0\"" >&2
		return $LINENO
	else
		return 0
	fi
}


function writeLog () {

	#	set local log text
	local LOG_TEXT="$1"

	#	set local default log file path if not globally defined
	if [ -z "$LOG_PATH" ]; then 
		local LOG_PATH="${0%.*}.log"
	fi

	#	create log file if not found
	if [ ! -w "$LOG_PATH" ]; then
		if ! /usr/bin/touch "$LOG_PATH" 2> /dev/null; then
			echo "ERROR: Unable to create log file [$LOG_PATH]." >&2
			return $LINENO
		fi
	fi
	
	#	write to log file 
	if echo "`/bin/date +"%b %d %H:%M:%S"` $HOSTNAME ${0##*/}[$$] $LOG_TEXT" | /usr/bin/tee -a "$LOG_PATH"; then 
			return 0
	else
			echo "ERROR: Unable to create log file [$LOG_PATH]." >&2
			return $LINENO
	fi
}


function setCustomDefaults () {

	local SYSTEM_PREFERENCES="/Library/Preferences"
	local HOME_DIRECTORY=`/usr/bin/dscl . read /Users/$USERNAME NFSHomeDirectory | /usr/bin/awk '{print $2}'`
	local XML_START_LINE=`/usr/bin/awk '/^__XML_FOLLOWS__/ {print NR + 1; exit 0;}' "$0"`
	local XML_PREFERENCES=`/usr/bin/tail +$XML_START_LINE "$0"`
	local COUNT=`echo $XML_PREFERENCES | /usr/bin/xpath "count(//preference)" 2> /dev/null`
	
	for (( PREF_INDEX=1; PREF_INDEX<=$COUNT; PREF_INDEX++ )); do
		
		#	query node attributes
		CLASS=`echo $XML_PREFERENCES | /usr/bin/xpath "string(/preferences/preference[$PREF_INDEX]/@class)" 2> /dev/null`	
		DOMAIN=`echo $XML_PREFERENCES | /usr/bin/xpath "string(/preferences/preference[$PREF_INDEX]/@domain)" 2> /dev/null`
		KEY=`echo $XML_PREFERENCES | /usr/bin/xpath "string(/preferences/preference[$PREF_INDEX]/@key)" 2> /dev/null`      
		TYPE=`echo $XML_PREFERENCES | /usr/bin/xpath "string(/preferences/preference[$PREF_INDEX]/@type)" 2> /dev/null`		
		VALUE=`echo $XML_PREFERENCES | /usr/bin/xpath "string(/preferences/preference[$PREF_INDEX]/@value)" 2> /dev/null`  
		
		###	process each preference for class of "user"	
		if [ "$CLASS" == "user" ]; then

			#	write user preferences to home directoy if exist
			if [ -d "$HOME_DIRECTORY/Library/Preferences" ]; then 

				#	get owner of current home directory
				OWNER=`/usr/bin/stat -f %Su:%Sg "$HOME_DIRECTORY/Library/Preferences"`

				if /usr/bin/defaults write "$HOME_DIRECTORY/Library/Preferences/$DOMAIN" $KEY -${TYPE} $VALUE 2> /dev/null; then
					echo "Updated [$HOME_DIRECTORY/Library/Preferences/$DOMAIN] with KEY: $KEY TYPE: $TYPE VALUE: $VALUE."

					#	reset permissions after updating
					/bin/chmod 0755  "$HOME_DIRECTORY/Library/Preferences/${DOMAIN}.plist" 2> /dev/null
					/usr/sbin/chown $OWNER "$HOME_DIRECTORY/Library/Preferences/${DOMAIN}.plist"	2> /dev/null		
				else
					echo "ERROR: Unable to write key [$KEY] to [$HOME_DIRECTORY/Library/Preferences/$DOMAIN]." &>2
				fi
			fi

		### process each preference for class "system"
		elif [ "$CLASS" == "system" ]; then

			#	write system preferences to default location 
			if /usr/bin/defaults write "$SYSTEM_PREFERENCES/$DOMAIN" $KEY -${TYPE} $VALUE 2> /dev/null && /bin/chmod 0644 "$SYSTEM_PREFERENCES/$DOMAIN.plist"; then
				echo "Updated [$SYSTEM_PREFERENCES/$DOMAIN] with KEY: $KEY TYPE: $TYPE VALUE: $VALUE."
			else
				echo "ERROR: Unable to write key [$KEY] to [$SYSTEM_PREFERENCES/$DOMAIN]." &>2
			fi

		###	process each preference 
		elif [ "$CLASS" == "byhost" ]; then

			#	write host specific preference for class "byhost"

			if [ -d "$HOME_DIRECTORY/Library/Preferences/ByHost" ]; then 

				#	get owner of current home directory
				OWNER=`/usr/bin/stat -f %Su:%Sg "$HOME_DIRECTORY/Library/Preferences/ByHost"`

				if /usr/bin/defaults -currentHost write "$HOME_DIRECTORY/Library/Preferences/$DOMAIN" $KEY -${TYPE} $VALUE 2> /dev/null; then
					echo "Updated [$HOME_DIRECTORY/Library/Preferences/ByHost/$DOMAIN] with KEY: $KEY TYPE: $TYPE VALUE: $VALUE."

					#	reset permissions after updating
					/bin/chmod 0755  "$HOME_DIRECTORY/Library/Preferences/ByHost/${DOMAIN}.plist" 2> /dev/null
					/usr/sbin/chown $OWNER "$HOME_DIRECTORY/Library/Preferences/ByHost/${DOMAIN}.plist"	2> /dev/null		
				else
					echo "ERROR: Unable to write key [$KEY] to [$HOME_DIRECTORY/Library/Preferences/ByHost/$DOMAIN]." &>2
				fi
			fi
		fi
	done

	if /usr/bin/pgrep cfprefsd &> /dev/null; then /usr/bin/pkill cfprefsd; fi
	if /usr/bin/pgrep Finder &> /dev/null; then /usr/bin/pkill Finder; fi
	if /usr/bin/pgrep Dock &> /dev/null; then /usr/bin/pkill Dock; fi
}


function main () {

	if isRoot; then
		setCustomDefaults 2>&1 | (while read INPUT; do writeLog "$INPUT "; done)
	fi
}


if [[ "$BASH_SOURCE" == "$0" ]]; then
	main
fi

exit
#	the xml payload that follows can be modified to suit
#	your company's custom settings. the xml data below is
#	case-specific so keep that in mind.


#	I compiled the xml data below from differnt versions of
#	macOS and may not be suitable for all systems. use at
#	your own risk.
 

__XML_FOLLOWS__
<?xml version="1.0"?>
<preferences>
	<!--    start user class preferences    -->
	<preference class="user" domain=".GlobalPreferences" key="NSQuitAlwaysKeepsWindows" type="bool" value="false"/>
	<preference class="user" domain=".GlobalPreferences" key="AppleActionOnDoubleClick" type="string" value="Maximize"/>
	<preference class="user" domain=".GlobalPreferences" key="com.apple.trackpad.forceClick" type="bool" value="false"/>
	<preference class="user" domain=".GlobalPreferences" key="com.apple.swipescrolldirection" type="bool" value="false"/>
	<preference class="user" domain=".GlobalPreferences" key="NSAutomaticDashSubstitutionEnabled" type="bool" value="false"/>
	<preference class="user" domain=".GlobalPreferences" key="NSAutomaticQuoteSubstitutionEnabled" type="bool" value="false"/>
	<preference class="user" domain="com.apple.desktopservices" key="DSDontWriteNetworkStores" type="bool" value="true"/>
	<preference class="user" domain="com.apple.desktopservices" key="DSDontWriteUSBStores" type="bool" value="true"/>
	<preference class="user" domain="com.apple.dock" key="minimize-to-application" type="bool" value="true"/>
	<preference class="user" domain="com.apple.dock" key="wvous-br-corner" type="int" value="6"/>
	<preference class="user" domain="com.apple.dock" key="wvous-br-modifier" type="int" value="0"/>
	<preference class="user" domain="com.apple.dock" key="wvous-bl-corner" type="int" value="5"/>
	<preference class="user" domain="com.apple.dock" key="wvous-bl-modifier" type="int" value="0"/>
	<preference class="user" domain="com.apple.dock" key="wvous-tr-corner" type="int" value="10"/>
	<preference class="user" domain="com.apple.dock" key="wvous-tr_modifier" type="int" value="0"/>
	<preference class="user" domain="com.apple.finder" key="_FXShowPosixPathInTitle" type="bool" value="true"/>
	<preference class="user" domain="com.apple.finder" key="_FXSortFoldersFirst" type="bool" value="true"/>
	<preference class="user" domain="com.apple.finder" key="FXDefaultSearchScope" type="string" value="SCcf"/>
	<preference class="user" domain="com.apple.finder" key="FXPreferredSearchViewStyle" type="string" value="Nlsv"/>
	<preference class="user" domain="com.apple.finder" key="FXPreferredViewStyle" type="string" value="Nlsv"/>
	<preference class="user" domain="com.apple.finder" key="ShowPathBar" type="bool" value="true"/>
	<preference class="user" domain="com.apple.finder" key="ShowStatusBar" type="bool" value="true"/>
	<preference class="user" domain="com.apple.finder" key="NewWindowTarget" type="string" value="PfHm"/>
	<preference class="user" domain="com.apple.Safari" key="ShowFullURLInSmartSearchField" type="bool" value="true"/>
	<preference class="user" domain="com.apple.Safari" key="ShowStatusBar" type="bool" value="true"/>
	<preference class="user" domain="com.apple.Safari" key="NewTabBehavior" type="int" value="1"/>
	<preference class="user" domain="com.apple.Safari" key="NewWindowBehavior" type="int" value="1"/>
	<preference class="user" domain="com.apple.Safari" key="TabbedBrowsing" type="bool" value="true"/>
	<preference class="user" domain="com.apple.Safari" key="OpenExternalLinksInExistingWindow" type="bool" value="true"/>
	<preference class="user" domain="com.apple.Safari" key="OpenNewTabsInFront" type="bool" value="true"/>
	<preference class="user" domain="com.apple.TimeMachine" key="DoNotOfferNewDisksForBackup" type="bool" value="true"/>
	<preference class="user" domain="com.apple.universalaccess" key="closeViewScrollWheelPreviousToggle" type="bool" value="true"/>
	<preference class="user" domain="com.apple.universalaccess" key="closeViewScrollWheelToggle" type="bool" value="true"/>
	<!--    start system class preferences    -->
	<preference class="system" domain="com.apple.loginwindow" key="SHOWFULLNAME" type="bool" value="true"/>
	<preference class="system" domain="com.apple.loginwindow" key="AdminHostInfo" type="string" value="DSStatus"/>
	<preference class="system" domain="com.apple.networkauthorization" key="UseShortName" type="bool" value="true"/>
	<!--    start byhost class preferences    -->
	<preference class="byhost" domain=".GlobalPreferences" key="com.apple.mouse.tapBehavior" type="bool" value="true"/>
</preferences>