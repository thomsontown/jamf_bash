#!/bin/bash

#    This script was written to process the properties for
#    the setup assistant within macOS after initial install 
#    or upgrade of the operating system. The script utilizes
#    the actual OS version and build number of the new OS
#    to ensure only the required prompts at first-login are
#    displayed to the end user. 

#    For maximum efficiency, a pseudo multi-demensional array
#    is created where the individual settings can be modified.

#    Author:            Andrew Thomson
#    Date:              02-01-2017
#    GitHub:            https://github.com/thomsontown



#	if target not specified, then target is /
TARGET=${3:-/}


#	verify run as root
if [[ $EUID -ne 0 ]]; then
	(>&2 echo "ERROR: This script must run with root privileges.")
	exit $LINENO
fi


#	get list of home directories from target
HOME_DIRECTORIES=(`/usr/bin/dscl -f ${TARGET%/}/var/db/dslocal/nodes/Default localonly list /Local/Target/Users NFSHomeDirectory | /usr/bin/awk '{print $2}'`)


#	eliminate home directories without existing preferences
for INDEX in ${!HOME_DIRECTORIES[@]}; do
	if [ ! -d "${TARGET%/}${HOME_DIRECTORIES[$INDEX]%/}/Library/Preferences" ]; then
		unset HOME_DIRECTORIES[$INDEX] 
	fi
done


#	query os version 
if ! OS_VERSION=`/usr/bin/defaults read "${TARGET%/}/System/Library/CoreServices/SystemVersion" ProductVersion 2> /dev/null`; then 
	(>&2 echo "ERROR: Unable to determine OS Version.")
	exit $LINENO
fi 

 
#	query build version
if ! OS_BUILD=`/usr/bin/defaults read "${TARGET%/}/System/Library/CoreServices/SystemVersion" ProductBuildVersion 2> /dev/null`; then
	(>&2 echo "ERROR: Unable to determine OS Build.")
	exit $LINENO
fi


#	set preferences array
PREFERENCES=("DidSeeCloudSetup:bool:true" "DidSeeiCloudSecuritySetup:bool:true" "GestureMovieSeen:string:none" "LastCacheCleanupProductVersion:string:$OS_VERSION" "LastPreLoginTasksPerformedBuild:string:$OS_BUILD" "LastPreLoginTasksPerformedVersion:string:$OS_VERSION" "LastSeenCloudProductVersion:string:$OS_VERSION" "SkipFirstLoginOptimization:bool:true" "DidSeeSiriSetup:bool:true")


#	enumerate pseudo multi-demensional array where each
#	item contains a preference key, type and value
for PREF_INDEX in ${!PREFERENCES[@]}; do

	#	extract sub-array from each element
	#	of the parent array
	PREFERENCE=(${PREFERENCES[$PREF_INDEX]//:/ })

	#	split each item of the sub-array
	#	into individual variables
	IFS=" " read KEY TYPE VALUE <<< ${PREFERENCE[@]}

	#	enumerate preferences paths
	for INDEX in ${!HOME_DIRECTORIES[@]}; do

		#	get profile user
		HOME_USER=`/usr/bin/stat -f %Su "${TARGET%/}${HOME_DIRECTORIES[$INDEX]%/}/Library/Preferences/."`

		#	apply preference to profile
		if /usr/bin/defaults write "${TARGET%/}${HOME_DIRECTORIES[$INDEX]%/}/Library/Preferences/com.apple.SetupAssistant.plist" $KEY -${TYPE} $VALUE &> /dev/null; then
			echo "Updated key [$KEY] to user profile [${HOME_DIRECTORIES[$INDEX]%}]."

			#	reset permissions after updating
			/bin/chmod 0755 "${TARGET%/}${HOME_DIRECTORIES[$INDEX]%/}/Library/Preferences/com.apple.SetupAssistant.plist"
			/usr/sbin/chown $HOME_USER: "${TARGET%/}${HOME_DIRECTORIES[$INDEX]%/}/Library/Preferences/com.apple.SetupAssistant.plist"
		else
			(>&2 echo "ERROR: Unable to write key [$KEY] to user profile [${HOME_DIRECTORIES[$INDEX]%}].")
		fi
	done


	#	apply preference to template
	if /usr/bin/defaults write "${TARGET%/}/System/Library/User Template/Non_Localized/Library/Preferences/com.apple.SetupAssistant.plist" $KEY -${TYPE} $VALUE &> /dev/null; then
		echo "Updated key [$KEY] to user template."
	else
		(>&2 echo "ERROR: Unable to write key [$KEY] to user template.")
	fi
done