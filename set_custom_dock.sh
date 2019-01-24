#!/bin/bash


#.   This script was written to run from a JAMF PRO server where $3 specifies
#.   the current console user. Designed to run at login, this script will enumerate
#.   applications listed on the user's dock and remove any that are found in 
#.   the black list which is provided as an array from the main function.  

#.   Author:          Andrew Thomson
#.   Date:            01-23-2019
#.   GitHub:          https://github.com/thomsontown


USERNAME="$3"
LOG_PATH="/var/log/imaging_set_custom_dock.log"


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


function setCustomDock () {

	APPLICATION_BLACK_LIST=("$@")

	#	check username parameter
	if [[ -z $USERNAME ]]; then
		echo "ERROR: User name not specified." >&2
		return $LINENO
	fi

	#	check dock perferences
	local HOME_DIRECTORY=`/usr/bin/dscl . read /Users/$USERNAME NFSHomeDirectory | /usr/bin/awk '{print $2}'`
	if [ ! -f "$HOME_DIRECTORY/Library/Preferences/com.apple.dock.plist" ]; then 
		echo "ERROR: Unable to locate Dock perferences for [$USERNAME]."
		return $LINENO
	fi

	
	#	enumerate applications in user dock preference and remove any that are black listed
	for APPLICATION in "${APPLICATION_BLACK_LIST[@]}"; do

		#	get item index of current application
		INDEX=`/usr/libexec/PlistBuddy -c "Print :persistent-apps" "$HOME_DIRECTORY/Library/Preferences/com.apple.dock.plist" 2> /dev/null | /usr/bin/awk -F '=' '/CFURLString = /{print $2}' | /usr/bin/nl | /usr/bin/egrep -i "${APPLICATION// /%20}" | /usr/bin/awk '{print $1}'`

 		if [ -n "$INDEX" ]; then 

			#	modify the property list 		
			/usr/libexec/PlistBuddy -c "Delete :persistent-apps:'$((${INDEX} - 1))'" "$HOME_DIRECTORY/Library/Preferences/com.apple.dock.plist" 2> /dev/null
			
			#	save the modified property list
			if /usr/libexec/PlistBuddy -c save "$HOME_DIRECTORY/Library/Preferences/com.apple.dock.plist" &> /dev/null; then	 
				echo "Removed [$APPLICATION] from profile [$HOME_DIRECTORY]." 
			else
				echo "ERROR: Unable to remove [$APPLICATION] from profile [$HOME_DIRECTORY]." >&2
			fi
		else
			/bin/echo "Not found: [$APPLICATION] in profile [$HOME_DIRECTORY]."
		fi
	done


	if /usr/bin/pgrep cfprefsd &> /dev/null; then /usr/bin/killall cfprefsd; fi
	if /usr/bin/pgrep Dock &> /dev/null; then /usr/bin/killall Dock; fi
}


function main () {

	if isRoot; then 
		setCustomDock "Siri" "Launchpad" "Mail" "Contacts" "Calendar" "Notes" "Reminders" "Maps" "Photos" "Messages" "FaceTime" "News" "iTunes" "iBooks" "App Store" "System Preferences" 2>&1 | (while read INPUT; do writeLog "$INPUT "; done)
	fi
}


if [[ "$BASH_SOURCE" == "$0" ]]; then
	main
fi
