#!/bin/bash

APPLICATIONS=("Siri" "Launchpad" "Mail" "Contacts" "Calendar" "Notes" "Reminders" "Maps" "Photos" "Messages" "FaceTime" "iTunes" "iBooks" "App Store" "System Preferences")
RESTART=false


#	if target not specified, then target is /
TARGET=${3:-/}


#	verify run as root
if [[ $EUID -ne 0 ]]; then
	(>&2 echo "ERROR: This script must run with root privileges.")
	exit $LINENO
fi


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
	if [ ! -f "${TARGET%/}${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/com.apple.dock.plist" ]; then
		unset HOME_DIRECTORIES[$HOME_INDEX] 
	fi
done


#	enumerate profiles
for HOME_INDEX in ${!HOME_DIRECTORIES[@]}; do

	#	enumerate applications 
	for APP_INDEX in ${!APPLICATIONS[@]}; do

		#	get item index of current application
		ITEM_INDEX=`/usr/libexec/PlistBuddy -c "Print :persistent-apps" "${TARGET%/}${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/com.apple.dock.plist" 2> /dev/null | /usr/bin/awk -F '=' '/CFURLString = /{print $2}' | /usr/bin/nl | /usr/bin/egrep -i "${APPLICATIONS[$APP_INDEX]// /%20}" | /usr/bin/awk '{print $1}'`

		if [ -n "$ITEM_INDEX" ]; then 

			#	modify the property list 		
			/usr/libexec/PlistBuddy -c "Delete :persistent-apps:'$((${ITEM_INDEX} - 1))'" "${TARGET%/}${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/com.apple.dock.plist" 2> /dev/null
			
			#	save the modified property list
			if /usr/libexec/PlistBuddy -c save "${TARGET%/}${HOME_DIRECTORIES[$HOME_INDEX]%/}/Library/Preferences/com.apple.dock.plist" &> /dev/null; then	 
				echo "Removed [${APPLICATIONS[$APP_INDEX]}] from profile [${HOME_DIRECTORIES[$HOME_INDEX]%/}]." 
				RESTART=true
			else
				(>&2 echo "ERROR: Unable to remove [${APPLICATIONS[$APP_INDEX]}] from profile [${HOME_DIRECTORIES[$HOME_INDEX]%/}].")
			fi
		fi
	done
done    


#	restart dock
if /usr/bin/pgrep Dock &> /dev/null; then /usr/bin/pkill Dock; fi