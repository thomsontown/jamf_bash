#!/bin/bash


#.   This script was written to run from a JAMF PRO server at login where $3 specifies
#.   the current console user and $4 specifies the path to an image file that 
#.   will be set as the default wallpaper. Note: user profiles that have not 
#.   been individually customized through system preferences may also be affected. 

#.   Author:          Andrew Thomson
#.   Date:            01-23-2019
#.   GitHub:          https://github.com/thomsontown


USERNAME="$3"
PICTURE_PATH="$4"
LOG_PATH="/var/log/imaging_set_custom_wallpaper.log"


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


function setWallpaper () {

	local PICTURE_PATH="$1"
	local USERNAME="$2"

	#	check picture path parameter 
	if [ -z "$PICTURE_PATH" ] || [ ! -f "$PICTURE_PATH" ]; then
		echo "ERROR: Image not found or not specified." >&2 
		return $LINENO
	fi

	#	check username parameter
	if [[ -z $USERNAME ]]; then
		echo "ERROR: User name not specified." >&2
		return $LINENO
	fi

	#	verify minimum os version
	OS_VERSION=`/usr/bin/sw_vers -productVersion | /usr/bin/awk -F'.' '{print $2}'`
	if [ "${OS_VERSION//.}" -lt "10" ]; then
		echo "ERROR: The OS verison does not meet the minimum requirements." >&2
		return $LINENO
	fi

	#	modify symbolic links for image files
	IMAGE_FILES=("/System/Library/CoreServices/DefaultDesktop.jpg" "/System/Library/CoreServices/DefaultBackground.jpg" "/System/Library/CoreServices/DefaultDesktop.heic")
	for IMAGE_FILE in ${IMAGE_FILES[@]}; do
		if [ -L "$IMAGE_FILE" ]; then 
			local LINK_PATH=`/usr/bin/stat -f %Y "$IMAGE_FILE"`
			local LINK_EXT="${LINK_PATH##*.}"
			
			#	rename original image file
			if ! /bin/mv "$LINK_PATH" "${LINK_PATH%.*}.$RANDOM.$LINK_EXT" &> /dev/null; then
				echo "ERROR: Unable to rename linked image file. [$LINK_PATH]" >&2
				return $LINENO
			fi

			#	copy new image to original linked file path
			if ! /bin/cp -f "${PICTURE_PATH}" "${LINK_PATH}"; then
				echo "ERROR: Unable to copy image to link path." >&2
				return $LINENO
			fi
		fi
	done

	#	remove desktop picture databases
	local HOME_DIRECTORY=`/usr/bin/dscl . read /Users/$USERNAME NFSHomeDirectory | /usr/bin/awk '{print $2}' 2> /dev/null`
	if [ -f "$HOME_DIRECTORY/Library/Application Support/Dock/desktoppicture.db" ]; then
		echo "Resetting picture database for user profile [$USERNAME]."
		/bin/rm "$HOME_DIRECTORY/Library/Application Support/Dock/desktoppicture.db" &> /dev/null
	fi


	#	remove desktop picture caches for user profiles (not using desktoppicture.db)
	PICTURE_CACHES=(`/usr/bin/find /var/folders -type d -name com.apple.desktoppicture 2> /dev/null`)
	for PICTURE_CACHE in ${PICTURE_CACHES[@]}; do
		if ! /bin/rm -rf "$PICTURE_CACHE"; then
			echo "ERROR: Unable to remove cached desktop picture [$PICTURE_CACHE]." >&2
		fi
	done

	#	replace desktop picture cache for login window
	if [ -f "/Library/Caches/com.apple.desktop.admin.png" ]; then 
		/usr/bin/chflags nouchg "/Library/Caches/com.apple.desktop.admin.png" &> /dev/null
		/bin/rm -f "/Library/Caches/com.apple.desktop.admin.png"
	fi

	if ! /usr/bin/sips -s format png "$PICTURE_PATH" --out "/Library/Caches/com.apple.desktop.admin.png" &> /dev/null; then 
		/bin/echo "ERROR: Unable to reformat speficied desktop image." >&2
	else
		/usr/sbin/chown root:wheel "/Library/Caches/com.apple.desktop.admin.png" &> /dev/null
		/bin/chmod 755 "/Library/Caches/com.apple.desktop.admin.png" &> /dev/null
		/usr/bin/chflags uchg "/Library/Caches/com.apple.desktop.admin.png" &> /dev/null
	fi

	#	rebuild cache (CoreStorage only)
	if [ -f "/System/Library/Caches/com.apple.corestorage/EFILoginLocalizations" ]; then
		/usr/bin/touch "/System/Library/Caches/com.apple.corestorage/EFILoginLocalizations"
		/usr/sbin/kextcache -fu /
	fi

	#	refresh dock
	if /usr/bin/pgrep Dock &> /dev/null; then /usr/bin/pkill Dock; fi
}


function main () { 

	if isRoot; then 
		setWallpaper "$PICTURE_PATH" "$USERNAME" 2>&1 | (while read INPUT; do writeLog "$INPUT "; done)
	fi
}


if [[ "$BASH_SOURCE" == "$0" ]]; then
	main
fi