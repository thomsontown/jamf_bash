#!/bin/bash

#    This script was written to run from the JSS and allow
#    the 4th parameter in the policy to specify the path
#    to the updated default wallpaper.

#    Alternatively, it could also be added as a postinstall
#    script within a package file that distributes a new 
#    image that is intended to be set as desktop wallpaper.

#    Unlike many of the scripts I've seen elsewhere, this
#    script will enumerate each user profile and update 
#    each desktop database with the new wallpaper.

#    Additionally, the wallpaper image symbolically linked
#    to the default image is replaced with a copy of the
#    updated image. A backup copy of the original is made
#    for safe keeping.

#    Author:        Andrew Thomson
#    Date:          06/23/2015
#    GitHub:        https://github.com/thomsontown


#	if target not specified, then target is /
TARGET=${3:-/}


#	if picture path not specified, then use default path
PICTURE_PATH=${4:-"$TARGET/Library/Desktop Pictures/Frog.jpg"}


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
for INDEX in ${!HOME_DIRECTORIES[@]}; do
	if [ ! -f "${TARGET%/}${HOME_DIRECTORIES[$INDEX]%/}/Library/Application Support/Dock/desktoppicture.db" ]; then
		unset HOME_DIRECTORIES[$INDEX] 
	fi
done


#	verify minimum os version
OS_VERSION=`/usr/bin/sw_vers -productVersion`
if [ "${OS_VERSION//.}" -lt "10100" ]; then
	(>&2 echo "ERROR: The OS verison does not meet the minimum requirements.")
	exit $LINENO
fi


#	check required parameters 
if [ -z "$PICTURE_PATH" ] || [ ! -f "$PICTURE_PATH" ]; then
	(>&2 echo "ERROR: Image not found or not specified.")
	exit $LINENO
fi


#	get current default desktop symlink
LINK_PATH=`/usr/bin/stat -f %Y "${TARGET%/}/System/Library/CoreServices/DefaultDesktop.jpg"` 


#	validate default desktop returned a symlink
if [ -n "${TARGET%/}$LINK_PATH" ]; then
	
	#	rename linked file if they are not the same
	if [ -f "${TARGET%/}${LINK_PATH}" ] && [ "${TARGET%/}$LINK_PATH" != "$PICTURE_PATH" ]; then
		
		if ! /bin/mv "${TARGET%/}${LINK_PATH}" "${TARGET%/}${LINK_PATH}.$RANDOM"; then
			(>&2 echo "ERROR: Unable to rename linked image file.")
			exit $LINENO
		fi
		
		#	copy new image to original linked file path
		if ! /bin/cp -f "${PICTURE_PATH}" "${TARGET%/}${LINK_PATH}"; then
			(>&2 echo "ERROR: Unable to copy image to link path.")
			exit $LINENO
		fi
	fi
fi		


#	enumerate home directories
for INDEX in ${!HOME_DIRECTORIES[@]}; do

	#	get profile user
	OWNER=`/usr/bin/stat -f %u:%g "${TARGET%/}${HOME_DIRECTORIES[$INDEX]%/}/Library/Application Support/Dock/desktoppicture.db"`

	#	skip local user if no existing database is found 
	if [ ! -f "${TARGET%/}${HOME_DIRECTORIES[$INDEX]%/}/Library/Application Support/Dock/desktoppicture.db" ]; then continue; fi

	#	display debug info	
	if $DEBUG; then echo "Updating profile [${HOME_DIRECTORIES[$INDEX]%/}]"; fi

	#	modify local user desktop picture database
	/usr/bin/sqlite3 "${TARGET%/}${HOME_DIRECTORIES[$INDEX]%/}/Library/Application Support/Dock/desktoppicture.db" "UPDATE data SET value = \"$PICTURE_PATH\""
done


#	replace desktop picture cache for login window
if [ -f "${TARGET%/}/Library/Caches/com.apple.desktop.admin.png" ]; then /bin/rm -f "${TARGET%/}/Library/Caches/com.apple.desktop.admin.png"; fi

if ! /usr/bin/sips -s format png "$PICTURE_PATH" --out "${TARGET%/}/Library/Caches/com.apple.desktop.admin.png" &> /dev/null; then 
	(>&2 /bin/echo "ERROR: Unable to reformat speficied desktop image.")
else
	/usr/sbin/chown root:wheel "${TARGET%/}/Library/Caches/com.apple.desktop.admin.png" &> /dev/null
	/bin/chmod 755 "${TARGET%/}/Library/Caches/com.apple.desktop.admin.png" &> /dev/null
	/usr/bin/chflags uchg "${TARGET%/}/Library/Caches/com.apple.desktop.admin.png" &> /dev/null
fi


#	remove desktop picture caches for user profiles (not using desktoppicture.db)
PICTURE_CACHES=(`/usr/bin/find ${TARGET%/}/var/folders -type d -name com.apple.desktoppicture`)
for PICTURE_CACHE in ${PICTURE_CACHES[@]}; do
	if ! /bin/rm -rf "$PICTURE_CACHE"; then
		(>&2 echo "ERROR: Unable to remove cached desktop picture.")
	fi
done


#	rebuild cache
/usr/bin/touch "${TARGET%/}/System/Library/Caches/com.apple.corestorage/EFILoginLocalizations"
/usr/sbin/kextcache -fu ${TARGET}


#	refresh dock
if /usr/bin/pgrep Dock &> /dev/null; then /usr/bin/pkill Dock; fi