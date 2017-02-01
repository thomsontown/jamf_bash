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


#	set preferences array
PREFERENCES=("DidSeeCloudSetup:bool:true" "DidSeeiCloudSecuritySetup:bool:true" "GestureMovieSeen:string:none" "LastCacheCleanupProductVersion:string:$OS_VERSION" "LastPreLoginTasksPerformedBuild:string:$OS_BUILD" "LastPreLoginTasksPerformedVersion:string:$OS_VERSION" "LastSeenCloudProductVersion:string:$OS_VERSION" "SkipFirstLoginOptimization:bool:true" "DidSeeSiriSetup:bool:true")


#	set preferences paths
SYSTEM_TEMPLATE_PATH="/System/Library/User Template/Non_localized/Library/Preferences/com.apple.SetupAssistant"
DEFAULT_LIBRARY_PATH="/Library/Preferences/com.apple.SetupAssistant"


#	query os version and build number
OS_VERSION=`/usr/bin/defaults read "/System/Library/CoreServices/SystemVersion" ProductVersion`
OS_BUILD=`/usr/bin/defaults read "/System/Library/CoreServices/SystemVersion" ProductBuildVersion`


#	query direcotry for list of local users
LOCAL_USERS=(`/usr/bin/dscl . list /Users UniqueID | awk '$2 > 500 {print $1}'`)


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


#	enumerate pseudo multi-demensional array where each
#	item contains a preference key, type and value
for INDEX in ${!PREFERENCES[@]}; do

	#	extract sub-array from each element
	#	of the parent array
	PREFERENCE=(${PREFERENCES[$INDEX]//:/ })

	#	split each item of the sub-array
	#	into individual variables
	read KEY TYPE VALUE <<< ${PREFERENCE[@]}

	#	write preferences to user templates 
	if /usr/bin/defaults write "${SYSTEM_TEMPLATE_PATH}" $KEY -${TYPE} $VALUE 2> /dev/null; then
		echo "Updated user template with KEY: $KEY TYPE: $TYPE VALUE: $VALUE."
	else
		echo "ERROR: Unable to write key [$KEY] to user template."
	fi

	#	write preferences to each user profile
	for LOCAL_USER in ${LOCAL_USERS[@]}; do

		#	get home directory for local user 
		USER_HOME=`/usr/bin/dscl  . read /Users/$LOCAL_USER NFSHomeDirectory | awk '{ print $2 }'`

		#	skip local user if no existing preferences are found 
		if [ ! -d "${USER_HOME%/}/Library/Preferences" ]; then continue; fi

		#	write preferences to local user profile 
		if /usr/bin/sudo -u $LOCAL_USER /usr/bin/defaults write "${USER_HOME%/}$DEFAULT_LIBRARY_PATH" $KEY -${TYPE} $VALUE 2> /dev/null; then
		
			echo "Updated user profile [$LOCAL_USER] with KEY: $KEY TYPE: $TYPE VALUE: $VALUE."
		else
			echo "ERROR: Unable to write key [$KEY] to user profile [$LOCAL_USER]."
		fi
	done
done