#!/bin/bash

#    This script was written to run from the JSS and allow
#    the 4th parameter in the policy to specify the path
#    to the updated default wallpaper.

#    Unlike many of the scripts I've seen elsewhere, this
#    script will enumerate each user profile and update 
#    each desktop database with the new wallpaper.

#    Additionally, the wallpaper image symbolically linked
#    to the default image is replaced with a copy of the
#    updated image. A backup copy of the original is made
#    for safe keeping.

#    This script was designed for macOS 10.12.x and above.

#    Author:        Andrew Thomson
#    Date:          06/23/2015


#	set variables
PICTURE_PATH=$4


#	verify script is run as root
if [ $EUID -ne 0 ]; then
	echo "ERROR: Script must run as root."
	exit $LINENO
fi


#	verify minimum os version
OS_VERSION=`/usr/bin/sw_vers -productVersion`
if [ "${OS_VERSION//.}" -lt "10100" ]; then
	echo "ERROR: The OS verison does not meet the minimum requirements."
	exit $LINENO
fi


#	check required parameters 
if [ -z "$PICTURE_PATH" ]; then
	echo "ERROR: No image file specified."
	exit $LINENO
fi


#	check image file 
if [ ! -f "$PICTURE_PATH" ]; then 
	echo "ERROR: The specified image cannot be found."
	exit $LINENO
fi


#	query direcotry for list of local users
LOCAL_USERS=(`/usr/bin/dscl . list /Users UniqueID | awk '$2 > 500 {print $1}'`)


#	get current default desktop symlink
LINK_PATH=`/usr/bin/stat -f %Y /System/Library/CoreServices/DefaultDesktop.jpg` 


#	validate default desktop returned a symlink
if [ -n "$LINK_PATH" ]; then
	
	#	rename linked file if they are not the same
	if [ -f "${LINK_PATH}" ] && [ "$LINK_PATH" != "$PICTURE_PATH" ]; then
		
		if ! /bin/mv "${LINK_PATH}" "${LINK_PATH}.$RANDOM"; then
			echo "ERROR: Unable to rename linked image file."
			exit $LINENO
		fi
		
		#	copy new image to original linked file path
		if ! /bin/cp -f "${PICTURE_PATH}" "${LINK_PATH}"; then
			echo "ERROR: Unable to copy image to link path."
			exit $LINENO
		fi
	fi
fi		


#	enumerate local users
for LOCAL_USER in ${LOCAL_USERS[@]}; do 

	#	get local user's home directory
	LOCAL_USER_HOME=`/usr/bin/dscl  . read /Users/$LOCAL_USER NFSHomeDirectory | awk '{ print $2 }'`

	#	skip local user if no existing database is found 
	if [ ! -f "${LOCAL_USER_HOME%/}/Library/Application Support/Dock/desktoppicture.db" ]; then continue; fi

	#	display debug info	
	if $DEBUG; then echo "Updating profile: $LOCAL_USER . . ."; fi

	#	modify local user desktop picture database
	/usr/bin/sqlite3 "${LOCAL_USER_HOME%/}/Library/Application Support/Dock/desktoppicture.db" "UPDATE data SET value = \"$PICTURE_PATH\""
done


#	refresh desktop
/usr/bin/killall Dock