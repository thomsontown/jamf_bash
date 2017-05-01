#!/bin/bash 


#    This script is similar to my property list processor script but instead
#    of using xml to store the property list data, I use a pseudo-multi-dimnsional 
#    array. It turns out that during some environments perl (used in xpath)
#    is not available. 

#    Author:        Andrew Thomson
#    Date:          03/21/2017
#    GitHub:        https://github.com/thomsontown


#	set user preferences array
USER_PREFERENCES=(".GlobalPreferences:NSQuitAlwaysKeepsWindows:bool:false" \
	".GlobalPreferences:AppleActionOnDoubleClick:string:Maximize" \
	".GlobalPreferences:AppleMiniaturizeOnDoubleClick:bool:false" \
	"com.apple.AppleBluetoothMultitouch.trackpad:Clicking:bool:true" \
	"com.apple.AppleBluetoothMultitouch.trackpad:TrackpadRightClick:bool:true" \
	"com.apple.AppleBluetoothMultitouch.trackpad:TrackpadScroll:bool:true" \
	"com.apple.AppleBluetoothMultitouch.trackpad:HIDScrollZoomModifierMask:int:262144" \
	"com.apple.AppleMultitouchTrackpad:Clicking:bool:true" \
	"com.apple.AppleMultitouchTrackpad:TrackpadRightClick:bool:true" \
	"com.apple.AppleMultitouchTrackpad:TrackpadScroll:bool:true" \
	"com.apple.AppleMultitouchTrackpad:HIDScrollZoomModifierMask:int:262144" \
	"com.apple.CrashReporter:DialogType:string:none" \
	"com.apple.desktopservices:DSDontWriteNetworkStores:bool:true" \
	"com.apple.desktopservices:DSDontWriteUSBStores:bool:true" \
	"com.apple.dock:minimize-to-application:bool:true" \
	"com.apple.dock:wvous-br-corner:int:6" \
	"com.apple.dock:wvous-br-modifier:int:0" \
	"com.apple.dock:wvous-bl-corner:int:5" \
	"com.apple.dock:wvous-bl-modifier:int:0" \
	"com.apple.dock:wvous-tr-corner:int:10" \
	"com.apple.dock:wvous-tr_modifier:int:0" \
	"com.apple.finder:_FXShowPosixPathInTitle:bool:true" \
	"com.apple.finder:_FXSortFoldersFirst:bool:true" \
	"com.apple.finder:FXDefaultSearchScope:string:SCcf" \
	"com.apple.finder:ShowPathBar:bool:true" \
	"com.apple.finder:ShowStatusBar:bool:true" \
	"com.apple.finder:NewWindowTarget:string:PfHm" \
	"com.apple.finder:FXPreferredViewStyle:string:Nlsv" \
	"com.apple.loginwindow:SHOWFULLNAME:bool:true" \
	"com.apple.loginwindow:AdminHostInfo:string:DSStatus" \
	"com.apple.loginwindow:LoginwindowLaunchesRelaunchApps:bool:false" \
	"com.apple.loginWindow:TALLogoutSavesState:bool:false" \
	"com.apple.Safari:ShowFullURLInSmartSearchField:bool:true" \
	"com.apple.Safari:ShowStatusBar:bool:true" \
	"com.apple.Safari:NewTabBehavior:int:1" \
	"com.apple.Safari:NewWindowBehavior:int:1" \
	"com.apple.Safari:TabbedBrowsing:bool:true" \
	"com.apple.Safari:OpenExternalLinksInExistingWindow:bool:true" \
	"com.apple.Safari:OpenNewTabsInFront:bool:true" \
	"com.apple.TimeMachine:DoNotOfferNewDisksForBackup:bool:true" \
	"com.apple.universalaccess:closeViewScrollWheelToggle:bool:true" \
	)


#	set system preferences array
SYSTEM_PREFERENCES=("com.apple.AppleBluetoothMultitouch.trackpad:Clicking:bool:true" \
	"com.apple.AppleBluetoothMultitouch.trackpad:TrackpadRightClick:bool:true" \
	"com.apple.AppleBluetoothMultitouch.trackpad:TrackpadScroll:bool:true" \
	"com.apple.AppleMultitouchTrackpad:Clicking:bool:true" \
	"com.apple.AppleMultitouchTrackpad:TrackpadRightClick:bool:true" \
	"com.apple.AppleMultitouchTrackpad:TrackpadScroll:bool:true" \
	"com.apple.loginwindow:SHOWFULLNAME:bool:true" \
	"com.apple.loginwindow:AdminHostInfo:string:DSStatus" \
	"com.apple.networkauthorization:UseShortName:bool:true" \
	)

#	if target not specified, then target is /
TARGET=${3:-/}


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
for HOME_DIR_INDEX in ${!HOME_DIRECTORIES[@]}; do
	if [ ! -d "${TARGET%/}${HOME_DIRECTORIES[$HOME_DIR_INDEX]%/}/Library/Preferences" ]; then
		unset HOME_DIRECTORIES[$HOME_DIR_INDEX] 
	fi
done


#	apply user preferences
for USER_PREF_INDEX in ${!USER_PREFERENCES[@]}; do

	#	extract sub-array from each element
	#	of the parent array
	USER_PREFERENCE=(${USER_PREFERENCES[$USER_PREF_INDEX]//:/ })

	#	split each item of the sub-array
	#	into individual variables
	IFS=" " read DOMAIN KEY TYPE VALUE <<< ${USER_PREFERENCE[@]}

	#	enumerate home directories
	for HOME_DIR_INDEX in ${!HOME_DIRECTORIES[@]}; do

		#	get directory user and group
		OWNER=`/usr/bin/stat -f %u:%g "${TARGET%/}${HOME_DIRECTORIES[$HOME_DIR_INDEX]%/}/Library/Preferences/."`

		#	apply user preference 
		if /usr/bin/defaults write "${TARGET%/}${HOME_DIRECTORIES[$HOME_DIR_INDEX]%/}/Library/Preferences/${DOMAIN}.plist" $KEY -${TYPE} $VALUE &> /dev/null; then
			echo "Updated key [$KEY] to user profile [${HOME_DIRECTORIES[$HOME_DIR_INDEX]%}]."

			#	reset permissions after updating
			/bin/chmod 0755 "${TARGET%/}${HOME_DIRECTORIES[$HOME_DIR_INDEX]%/}/Library/Preferences/${DOMAIN}.plist" &> /dev/null
			/usr/sbin/chown $OWNER "${TARGET%/}${HOME_DIRECTORIES[$HOME_DIR_INDEX]%/}/Library/Preferences/${DOMAIN}.plist" &> /dev/null
		else
			(>&2 echo "ERROR: Unable to write key [$KEY] to user profile [${HOME_DIRECTORIES[$HOME_DIR_INDEX]%}].")
		fi
	done

	#	apply user template preferences
	if /usr/bin/defaults write "${TARGET%/}/System/Library/User Template/Non_Localized/Library/Preferences/${DOMAIN}.plist" $KEY -${TYPE} $VALUE &> /dev/null; then
		echo "Updated key [$KEY] to user template."
	else
		(>&2 echo "ERROR: Unable to write key [$KEY] to user template.")
	fi

	echo -e "\r"
done


#	apply system preferences
for SYSTEM_PREF_INDEX in ${!SYSTEM_PREFERENCES[@]}; do

	#	extract sub-array from each element
	#	of the parent array
	SYSTEM_PREFERENCE=(${SYSTEM_PREFERENCES[$SYSTEM_PREF_INDEX]//:/ })

	#	split each item of the sub-array
	#	into individual variables
	IFS=" " read DOMAIN KEY TYPE VALUE <<< ${SYSTEM_PREFERENCE[@]}

	#	apply system preference 
	if /usr/bin/defaults write "${TARGET%/}/System/Library/User Template/Non_localized/Library/Preferences/${DOMAIN}.plist" $KEY -${TYPE} $VALUE &> /dev/null; then
		echo "Updated key [$KEY] to system template preference."
	else
		(>&2 echo "ERROR: Unable to write key [$KEY] to system template preference.")
	fi
done

if /usr/bin/pgrep cfprefsd; then /usrbin/pkill cfprefsd; fi
if echo ${USER_PREFERENCES[@]} | /usr/bin/grep -i "com.apple.dock" &> /dev/null && /usr/bin/pgrep Dock &> /dev/null; then /usr/bin/pkill Dock; fi
if echo ${USER_PREFERENCES[@]} | /usr/bin/grep -i "com.apple.finder" &> /dev/null && /usr/bin/pgrep Finder &> /dev/null; then /usr/bin/pkill Finder; fi	
